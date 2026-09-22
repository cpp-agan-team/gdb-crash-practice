# 02：双 mutex 反序获取导致死锁

[返回练习首页](../../README.md) · [案例源码](main.cpp) · [GDB 自动脚本](inspect.gdb)

目标是建立完整证据链：两个工作线程分别持有哪把锁、等待哪把锁，最终如何形成循环等待。默认程序必定死锁；原子计数保证两个线程都持有第一把锁后，才尝试第二把锁，不依赖 sleep 或调度运气。

以下命令都从 Linux 的 Bash 执行：

```bash
make build/02_deadlock
gdb -q -nx --args build/02_deadlock
```

## 复现与手动中断

在 GDB 中输入：

```gdb
set pagination off
set debuginfod enabled off
set disable-randomization off
run
```

看到启动信息后，程序不会退出，也不会出现完成消息。等待约一秒后，**按键盘 Ctrl+C**，让 GDB 中断目标并返回提示符，再输入：

```gdb
info threads
thread apply all bt
```

如果中断过早、还停在线程创建或启动输出中，先 continue，再稍后 Ctrl+C，直到进入下述等待现场。

主要观察：

- 主线程通常在 join 对应的线程等待路径。
- 两个工作线程通常停在 mutex / futex 等锁等待路径。
- 栈中的 deadlock_worker 对应各线程尝试第二把锁的代码。

如果 GDB 提示 glibc 的某个 .c 文件找不到，表示本机没有那份库源码；已经显示的函数名、锁地址与应用栈仍可用于下面的核查。

线程切换本身不会继续执行程序。GDB 的线程编号是 info threads 左侧的编号；Linux TID 通常显示为 LWP 后面的数字。它们不是同一个编号，不能混用。不要假定工作线程每次一定编号为 2、3。

## 从等待栈走到锁的对应关系

先在任意线程打印全局诊断记录：

```gdb
p &left_mutex
p &right_mutex
p worker_a
p worker_b
```

预期地址关系如下；ASLR 会使具体地址变化：

| 工作线程 | 已持有 held | 正在尝试 waiting_for |
|---|---|---|
| worker_a，worker_id=1 | &left_mutex | &right_mutex |
| worker_b，worker_id=2 | &right_mutex | &left_mutex |

这些诊断字段在默认案例中由所属线程写入，并在原子计数发布后不再修改。held 在第一把锁成功获取后才设置；waiting_for 在尝试第二把锁前设置。它们不是通用 mutex 所有者接口，所以还要结合真实等待栈和源码确认。

选取一个工作线程：输入 thread 后加它的 **GDB 线程编号**；再用 bt 找到 deadlock_worker 所在帧，输入 frame 后加该帧编号。例如下面 N、F 都要替换为现场数字：

```gdb
thread N
bt
frame F
info args
p evidence->worker_id
p first
p second
list
```

再对另一个工作线程重复上述过程。first 与 second 分别对应当前线程已经持有及正在等待的锁。源码中 first_guard 在 second_guard 成功获取前不会析构，因此第一把锁不会提前释放。

在本案例验证过的 libstdc++ + glibc 环境中，还可补充查看：

```gdb
p left_mutex._M_mutex.__data.__owner
p right_mutex._M_mutex.__data.__owner
```

这里的 owner 是 Linux TID，应与 info threads 中的 LWP 核对：left 的 owner 属于 worker_a，right 的 owner 属于 worker_b。**这些都是实现内部字段，不属于 C++ 标准，也不是可移植的 glibc 调试 API。** libc / 标准库实现和版本不同，字段可能不存在或语义不同；不要据此编写生产代码。

最终关系是：

```text
worker_a --等待--> right_mutex --持有者--> worker_b
worker_b --等待--> left_mutex  --持有者--> worker_a
```

两个线程都无法先释放已持有的锁，形成循环等待。主线程的 join 只是等待工作线程结束，并非根因。**单独看到 pthread_mutex_lock / futex 栈不能证明死锁**：正常锁竞争也会产生类似栈，本例还展示了持有关系、等待关系和不可能自行解除的代码路径。

检查结束：

```gdb
kill
quit
```

根据 GDB 提示确认终止被调试程序；不要把这个必然挂起的程序留在后台。

## 自动核查真实等待现场

```bash
gdb -q -nx -batch -x cases/02_deadlock/inspect.gdb --args build/02_deadlock
```

脚本先在 deadlock_ready 停下，仅用该教学断点确认双方已经发布诊断信息；随后继续运行，让两个线程进入实际锁等待。GDB Python 的定时器只向当前 inferior PID 发送 SIGINT，自动完成手动 Ctrl+C 的中断步骤。

脚本验证实际 SIGINT 停止、两个工作线程的等待栈、锁地址形成的环，并在内部字段可用时核对 glibc owner 与 Linux TID。最后 kill 自己启动的目标，输出 [PASS] 02_deadlock。定时器只控制观察时机，死锁成立由原子同步和锁顺序保证。脚本需要带 Python 支持的 GDB；不是只在即将加锁的断点上推测死锁。

## 最小修复与验证

对于必须同时持有两把 mutex 的工作，C++17 可以统一获取：

```cpp
void deadlock_worker(WorkerEvidence* evidence,
                     std::mutex* first, std::mutex* second) {
    (void)evidence;
    std::scoped_lock both(*first, *second);
    // 在这里执行需要两把锁保护的工作。
}
```

同时删除 main 中等待 second_locks_attempted 以及 deadlock_ready 的教学同步代码；修复后的工作函数不再更新这些计数，否则 main 会等待一个永远不会发生的诊断条件。不能保留“持有两把锁后等另一个线程也获取锁”的原始教学屏障。

源文件已经以 FIX_BUG 宏提供上述修复，默认构建仍保留故障。独立编译并验证：

```bash
g++ -std=c++17 -O0 -g3 -fno-omit-frame-pointer \
  -Wall -Wextra -Wpedantic -pthread -DFIX_BUG \
  cases/02_deadlock/main.cpp -o build/02_deadlock_fixed
timeout 5s ./build/02_deadlock_fixed
echo $?
```

应打印 Both workers completed. 并返回 0；timeout 返回 124 表示没有按时完成，不能当成修复成功。固定全局加锁顺序也是可选修复，但所有参与同一组锁的路径都必须遵守。

