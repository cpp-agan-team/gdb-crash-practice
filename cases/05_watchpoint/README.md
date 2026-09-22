# 05：用 watch 找到修改变量的代码

[返回练习首页](../../README.md) · [案例源码](main.cpp) · [GDB 自动脚本](inspect.gdb)

本例没有越界、悬空指针或未定义行为：`Invoice` 始终有效，但折扣函数把“减去折扣”误写成“赋值为折扣”。预期金额为 270，实际变成 30。目标是从错误结果反查实际写入者。

## 编译与复现

以下是 Linux shell 命令：

```bash
mkdir -p build
g++ -std=c++17 -O0 -g3 -fno-omit-frame-pointer \
  -Wall -Wextra -Wpedantic -pthread \
  cases/05_watchpoint/main.cpp -o build/05_watchpoint
./build/05_watchpoint
echo $?
```

应输出 `total=30 expected=270`，退出码为 `1`。这是程序主动报告计算结果不符，程序没有崩溃。

## 第一步：在初始化完成后停下

启动 GDB：

```bash
gdb -q -nx --args build/05_watchpoint
```

然后在 GDB 输入：

```text
(gdb) set debuginfod enabled off
(gdb) set pagination off
(gdb) break demo::ready_for_watch
(gdb) run
(gdb) print invoice
```

重点观察 `quantity=3`、`unit_price=100`、`total=300`。断点所在函数由 `main` 在初始化之后调用，所以这些值有效。不要一进入 `main`、尚未执行局部对象初始化，就将其内存当作有效业务数据。

## 第二步：监控金额所在的内存位置

```text
(gdb) set $total_address = &invoice.total
(gdb) watch -location *$total_address
(gdb) info watchpoints
(gdb) continue
```

`$total_address` 是 GDB 的便利变量，保存本次运行里金额字段的地址。`watch -location` 固定监控该地址，避免断点函数返回后，其引用参数 `invoice` 离开作用域而影响观察点。真正的对象仍属于 `main`，在本例的折扣调用期间一直存活。

在本次 x86-64 WSL 验证环境中，GDB 使用硬件观察点。应看到：

```text
Old value = 300
New value = 30
```

这是实际写入改变了金额的证据。普通 `watch` 关注值发生变化；如果只是向 300 再写一次 300，不应期待同样的触发结果。[GDB 观察点文档](https://sourceware.org/gdb/current/onlinedocs/gdb.html/Set-Watchpoints.html)

## 第三步：用调用栈与参数解释错误

```text
(gdb) backtrace
(gdb) info args
(gdb) print invoice
(gdb) print discount
(gdb) list
```

当前业务帧应为 `demo::apply_discount`，上层包含 `main`；`discount=30`，数量和单价没有变化。检查附近的 `invoice.total = discount;`：程序确实把总价覆盖成折扣，而不是扣减折扣。

观察点触发时，写入已经发生。源码箭头可能落在赋值后面或函数右花括号，不能仅凭箭头指向下一行就把下一行当作写入者；结合旧值、新值和附近赋值语句判断。

看完后清理观察点，再完成本次运行：

```text
(gdb) delete breakpoints
(gdb) continue
(gdb) quit
```

`delete breakpoints` 在此教学会话中删除所有断点和观察点。交互模式可能询问是否确认，输入 `y`。冻结的地址不会随对象生命周期自动变成一个安全的“新对象观察点”；本例在对象退出生命周期前就将它删除。

## 最小修复与验证

将错误赋值改为：

```cpp
invoice.total -= discount;
```

源码已经用 `FIX_BUG` 提供这条修复分支，可独立构建验证，不需要编辑故障版：

```bash
g++ -std=c++17 -O0 -g3 -fno-omit-frame-pointer \
  -Wall -Wextra -Wpedantic -pthread -DFIX_BUG \
  cases/05_watchpoint/main.cpp -o build/05_watchpoint_fixed
./build/05_watchpoint_fixed
echo $?
```

应输出 `total=270 expected=270`，退出码 `0`。对修复版重复交互观察过程，会看到合法的 `300 → 270` 修改。观察点触发本身不代表有错误，必须结合业务期望判断。


