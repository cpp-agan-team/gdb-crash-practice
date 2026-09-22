# 01：空指针导致 SIGSEGV

[返回练习首页](../../README.md) · [案例源码](main.cpp) · [GDB 自动脚本](inspect.gdb)

这个案例练习从崩溃现场沿调用栈查到错误数据的来源。代码故意保留缺陷：`main` 把空的 `Order*` 交给 `process_request`，`calculate_total` 未检查便访问成员。在当前 Linux/GCC 调试构建中，运行到这次访问会收到 `SIGSEGV`。

## 问题、编译与复现

正常业务数据 `Order{3, 40}` 应得到总价 `120`；当前代码没有创建订单对象，因而无法得到有效总价。

以下是 **Shell 命令**，不是 GDB 命令：

```bash
mkdir -p build
g++ -std=c++17 -O0 -g3 -fno-omit-frame-pointer \
    -Wall -Wextra -Wpedantic -pthread \
    cases/01_segfault/main.cpp -o build/01_segfault
gdb -q -nx --args build/01_segfault
```

也可以使用根目录的 `make` 构建所有案例。

`-nx` 不读取个人 GDB 初始化文件。下方 `(gdb)` 是提示符，不需要输入。

## 一步步观察

1. 禁用在线下载调试符号，在解引用发生前停下。

   ```text
   (gdb) set pagination off
   (gdb) set debuginfod enabled off
   (gdb) break calculate_total
   (gdb) run
   ```

   应停在 `calculate_total` 的入口，参数显示 `order=0x0`。函数断点避免依赖可能变化的源码行号。

2. 检查参数与当前指令对应的源码。

   ```text
   (gdb) info args
   (gdb) print order
   (gdb) list calculate_total
   (gdb) bt
   ```

   主要看 `order` 是否为空、代码是否访问 `order->quantity`，以及栈是否包含 `calculate_total -> process_request -> main`。读取指针变量本身是安全的；此时不能把它当成有效 `Order` 对象。

3. 执行到真正发生故障的位置。

   ```text
   (gdb) continue
   (gdb) bt
   (gdb) print order
   ```

   应看到 `Program received signal SIGSEGV`，当前帧仍为 `calculate_total`，而 `order` 仍是 `0x0`。默认信号处理下，GDB 会先停住供检查，当前被调试进程尚未因这次信号完成退出。

4. 回到调用方，追踪空值是从哪里来的。

   ```text
   (gdb) frame 1
   (gdb) info args
   (gdb) list process_request
   (gdb) frame 2
   (gdb) info locals
   (gdb) list main
   ```

   `frame 1` 里参数仍为空，说明中间层只是转发；`frame 2` 里可看到 `main` 的局部变量 `order` 为空，源码明确执行了 `const Order* order = nullptr;`。这些帧编号来自本例刚查看的 `bt`，在其他程序中先看自己的栈再选择编号。

   切换栈帧只改变 GDB 当前查看的上下文，不会让程序回退执行。

5. 结束这次教学进程。

   ```text
   (gdb) quit
   ```

   如果 GDB 提示是否结束仍在运行的 inferior，输入 `y`。这里结束的只是本例由 GDB 启动的程序。

## 从现场证据推到原因

| 证据 | 能得出的判断 |
| --- | --- |
| 收到 `SIGSEGV` | 发生了非法内存访问，单凭信号还不能断定是空指针 |
| 当前语句访问 `order` 的成员，`order=0x0` | 本次访问使用了空指针 |
| 调用方参数和 `main` 局部变量均为空 | 空值来自上游，`calculate_total` 只是缺陷暴露的位置 |
| `main` 的源码直接初始化为空 | 本例的数据来源错误已经定位，无需猜测是分配器或线程问题 |

注意，一条源码语句可能对应多条机器指令。这里不需要仅凭行号判定究竟先读取了哪个成员；两个成员访问都要求 `order` 指向有效对象。

## 最小修复与检查

先在 build 下创建修复副本，保留原故障源码：

```bash
mkdir -p build
cp cases/01_segfault/main.cpp build/01_segfault_fixed.cpp
```

编辑 `build/01_segfault_fixed.cpp`，把 `main` 改成：

```cpp
int main() {
    const Order order{3, 40};
    std::cout << "total=" << process_request(&order) << '\n';
}
```

这使对象在整个同步调用期间保持有效。重新编译，再检查：

```bash
g++ -std=c++17 -O0 -g3 -fno-omit-frame-pointer \
    -Wall -Wextra -Wpedantic -pthread \
    build/01_segfault_fixed.cpp -o build/01_segfault_fixed
./build/01_segfault_fixed
```

预期输出 `total=120`，正常退出。实际 API 若允许“找不到订单”，还需要按业务约定拒绝请求、返回错误或抛出异常；不能把返回 `0` 自动当成正确业务处理。

本目录保留故障代码。验证记录已在临时副本中应用上面的修复并实际得到 `total=120`。

## 自动核查

以下脚本面向**未修复的教学代码**：

```bash
cd /home/codex/jisuanjizhishi/gdb-guide
gdb -q -nx -batch -x cases/01_segfault/inspect.gdb --args build/01_segfault
```

脚本断言空指针、三层调用栈以及 Linux 的 `SIGSEGV` 信号编号，最后打印 `[PASS] 01_segfault`。这里的 PASS 表示成功复现并识别预设缺陷；它不表示程序已修复。GDB 自身返回 `0`，与被调试程序发生段错误并不矛盾。

实际输出见 [verification.txt](verification.txt)。非空地址已替换为 `<address>`，行号、PID 和地址都不是复现实验的固定条件。


