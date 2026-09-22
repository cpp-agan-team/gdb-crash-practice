# 06：用 catch throw 找到未捕获异常的业务来源

[返回练习首页](../../README.md) · [案例源码](main.cpp) · [GDB 自动脚本](inspect.gdb)

配置中的工作线程数为 `-2`。业务校验抛出 `std::runtime_error`，但应用入口没有处理它，最终进入 `std::terminate` 并触发 `SIGABRT`。目标是区分“异常最初在哪里抛出”和“程序最后在哪里终止”。

## 编译与复现

以下是 Linux shell 命令：

```bash
mkdir -p build
g++ -std=c++17 -O0 -g3 -fno-omit-frame-pointer \
  -Wall -Wextra -Wpedantic -pthread \
  cases/06_exception/main.cpp -o build/06_exception
(ulimit -c 0; ./build/06_exception)
echo $?
```

子 shell 内的 `ulimit -c 0` 限制本次运行直接生成 core 文件，不修改系统配置或外层 shell 的限制；如果系统通过外部收集器处理 core，是否收集还取决于该收集器的策略。应看到未捕获的 `std::runtime_error` 及 `worker count must be positive`，程序被 `SIGABRT` 终止。在本例 Bash/Linux 环境下，shell 状态通常为 `134`（128 + SIGABRT 的信号编号 6）。

## 第一步：先观察最终终止现场

```bash
gdb -q -nx --args build/06_exception
```

在 GDB 输入：

```text
(gdb) set debuginfod enabled off
(gdb) set pagination off
(gdb) run
(gdb) backtrace
```

观察停止原因是 `SIGABRT`。栈顶可能位于 glibc 的信号发送代码或 `abort`，向上可看到 C++ 终止路径。系统库没有源码或完整调试符号不妨碍继续查看自己的业务代码。

这个现场说明程序走到了终止路径，不能仅因为栈顶是 `abort` 就判定 libc 有问题。`SIGABRT` 还有其他原因，如断言失败；本例应结合异常文本及调用栈判断。

## 第二步：重新运行，在 throw 时就停下

仍在同一 GDB 会话：

```text
(gdb) kill
(gdb) catch throw
(gdb) run
(gdb) backtrace
```

`kill` 只结束当前被调试程序，交互提示时输入 `y`。这次应先命中 C++ 异常捕获点，而不是等到 `SIGABRT`。

栈顶通常是运行库的异常支持函数，例如 `__cxa_throw`。从 backtrace 找到名为 `demo::parse_worker_count` 的业务帧，再输入 `up` 向上一层移动；如尚未到该函数，继续 `up`：

```text
(gdb) up
(gdb) info frame
```

帧号与运行库版本有关，不要照抄 `frame 1` 或 `frame 2`。每次用函数名确认已经进入正确的业务帧。本例的自动脚本也按函数名查找，而不写死帧号。

## 第三步：检查抛出条件与调用来源

选中 `demo::parse_worker_count` 帧以后：

```text
(gdb) info args
(gdb) print raw_count
(gdb) list
(gdb) backtrace
```

应看到 `raw_count=-2`，以及：

```cpp
if (raw_count <= 0) {
    throw std::runtime_error("worker count must be positive");
}
```

上层 `demo::start_server` 和 `main` 表明配置是如何进入校验函数的。证据链是：非法配置进入业务校验，校验按约定抛出异常，调用边界没有处理，程序最终终止。此处校验本身并不是需要删除的代码。

继续运行可观察后续终止：

```text
(gdb) continue
(gdb) backtrace
(gdb) kill
(gdb) quit
```

`continue` 后应收到 `SIGABRT`。在该处 `kill` 是清理当前调试进程，避免本次练习继续投递终止信号后留下 core。

## 最小修复与验证

对于配置失败，应在应用边界报告原因并受控退出，而不是带着无效配置继续启动：

```cpp
try {
    demo::start_server(configured_count);
} catch (const std::exception& error) {
    std::cerr << "configuration error: " << error.what() << '\n';
    return 2;
}
```

源码的 `FIX_BUG` 分支已包含这条修复：

```bash
g++ -std=c++17 -O0 -g3 -fno-omit-frame-pointer \
  -Wall -Wextra -Wpedantic -pthread -DFIX_BUG \
  cases/06_exception/main.cpp -o build/06_exception_fixed
./build/06_exception_fixed
echo $?
```

应输出 `configuration error: worker count must be positive`，受控退出码为 `2`，不再发生 `SIGABRT`。这仍然是启动失败，不应伪装成成功。合法配置的启动路径还应另行验证。

修复版依然会命中 `catch throw`：抛出异常与未捕获异常不是同一件事。用 `catch catch` 还可以观察处理器接住异常的事件。


