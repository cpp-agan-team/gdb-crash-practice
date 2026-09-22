# 03：continue 跳过进度更新，导致死循环

[返回练习首页](../../README.md) · [案例源码](main.cpp) · [GDB 自动脚本](inspect.gdb)

程序处理 8 个整数，约定跳过值为 0 的元素。当执行到下标 3 的零元素时，continue 跳过循环末尾的 ++index，从而反复读取同一元素。案例不依赖越界或有符号溢出：索引始终在数组范围内，计数采用无符号类型，回绕有明确定义。局部 zero_hits 声明为 volatile，使这个单线程教学循环每轮都有可观察访问，符合 C++17 的前进要求；这里的 volatile 不提供原子性，也不用于线程间同步。规则见 [C++17 N4659 的前进要求](https://timsong-cpp.github.io/cppwp/n4659/intro.progress)。

## 复现与中断

```bash
make build/03_infinite_loop
gdb -q -nx --args build/03_infinite_loop
```

在 GDB 中：

```gdb
set pagination off
set debuginfod enabled off
set disable-randomization off
run
```

启动后只打印开始信息，不会打印 completed。**按键盘 Ctrl+C** 中断，获得 GDB 提示符：

```gdb
bt
list
info threads
```

这里主要看线程是否仍在应用代码循环中，还是在锁、I/O 等等待中。中断位置可能是 process_items 内任一条循环语句，也可能在 items.size() / operator[] 这样的短小函数内部；停在这些函数不表示标准库本身有问题。

如果当前帧不是 process_items，用 bt 找到它，再执行 frame 加对应帧编号（下面 F 需替换）：

```gdb
frame F
info locals
p index
p checksum
p zero_hits
p items
```

应看到 index 为 3、checksum 为 28，数组下标 3 的元素为 0；zero_hits 已经很大。观察源码可知 checksum 等于此前处理的 4+9+15，说明进度卡在第 4 个元素。

## 多次观察：区分“执行很久”与“没有进展”

先记住或打印一次 zero_hits：

```gdb
p zero_hits
continue
```

稍后再按 Ctrl+C，重新用 bt / frame 选中 process_items，并打印：

```gdb
p index
p checksum
p zero_hits
```

主要看：index 和 checksum 不变，但 zero_hits 增长。这说明线程持续执行零值分支，却没有推进输入位置，而不是线程已经阻塞。

需要精确观察一次错误迭代时，先选中 process_items 帧，用 list process_items 找到 ++zero_hits 所在行。本版本是第 29 行，修改源码后要按实际行号调整：

```gdb
break cases/03_infinite_loop/main.cpp:29 if index == 3
continue
display index
display zero_hits
next
next
next
```

主要看 continue 如何回到循环条件，而循环末尾的 ++index 始终没有执行。这里设置的是当前循环内的断点；函数入口断点不会在同一次调用的每轮循环自动触发。执行完可用 info breakpoints 查看断点编号，再 delete 对应编号，避免再次 continue 时立刻命中。
## 从现场推导根因

1. 调用栈和多次中断表明线程在同一个循环持续执行。
2. 数组下标 3 为 0，确定每次都进入零值分支。
3. 该分支只有计数与 continue，没有改变 index。
4. continue 回到 while 条件；index 仍为 3，小于 8。
5. 因而下一轮仍读取同一零元素，没有能结束循环的进度变化。

只看到程序 CPU 高或多次停在一行，不能单独证明死循环。这里还检查了进度变量，并从控制流说明它为何永远不变。

GDB 线程编号不是 Linux TID；本例只有一个线程，不能将这种单线程现象直接推广到多线程服务。检查结束后：

```gdb
kill
quit
```

按提示确认终止自己的被调试程序。

## 自动核查

```bash
gdb -q -nx -batch -x cases/03_infinite_loop/inspect.gdb --args build/03_infinite_loop
```

脚本用 infinite_loop_ready 断点确认已到达零元素，然后删除断点并继续实际运行。带 Python 支持的 GDB 通过后台定时器两次只向自己的 inferior PID 发送 SIGINT，对应手工 Ctrl+C 的中断步骤。

断言检查两次真实中断都在 process_items 调用中，index=3、checksum=28 始终不变，而 zero_hits 确实增加。最后 kill 自己启动的目标，输出 [PASS] 03_infinite_loop。脚本未把停在教学断点本身当作死循环证据；也不使用 pkill / killall 影响其他程序。

## 最小修复与验证

既然零值元素的业务语义是“跳过”，跳过前必须推进索引：

```cpp
if (value == 0) {
    ++zero_hits;
    ++index;
    continue;
}
```

源文件通过 FIX_BUG 宏提供这个修复；默认构建保留故障。

```bash
cd /home/codex/jisuanjizhishi/gdb-guide
g++ -std=c++17 -O0 -g3 -fno-omit-frame-pointer \
  -Wall -Wextra -Wpedantic -pthread -DFIX_BUG \
  cases/03_infinite_loop/main.cpp -o build/03_infinite_loop_fixed
timeout 5s ./build/03_infinite_loop_fixed
echo $?
```

应输出 completed index=8 checksum=146 zero_hits=1，返回 0。timeout 返回 124 表示仍未按时完成，不能视为成功。修复不仅要能退出，还要验证非零元素都被处理，不能直接 break 丢弃剩余输入。

也可以用 for 循环统一维护索引更新，减少某条分支漏更新的机会；应保留原有“零值跳过”的语义。本例使用 -O0 帮助学习观察局部变量；真实优化构建可能出现内联、变量 optimized out 和源码行跳跃。具体实测记录见 verification.txt。
