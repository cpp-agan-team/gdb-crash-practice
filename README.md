# C++ GDB 最小故障练习

这里有六个故意保留 bug 的 C++ 小程序，用来练习：**复现问题 → 用 GDB 检查现场 → 根据证据找原因 → 修改并验证**。

每个案例的 README 都给出具体命令，并说明执行后主要看什么。先读对应案例、亲手调试，再用自动脚本核对结果。

## 1. 案例入口

| 案例 | 故障现象 | 重点观察 | 操作文档 |
|---|---|---|---|
| 01 空指针 | 程序收到 SIGSEGV | 崩溃语句、指针值、上层调用者传入的数据 | [空指针崩溃](cases/01_segfault/README.md) |
| 02 死锁 | 两个线程互相等待，程序不退出 | 所有线程的栈、各自持有和等待的锁、等待环 | [双锁死锁](cases/02_deadlock/README.md) |
| 03 死循环 | 一直执行，但处理进度不变 | 循环条件、索引、计数变化和 continue 分支 | [死循环](cases/03_infinite_loop/README.md) |
| 04 结果错误 | 正常退出，但平均值不正确 | 操作数类型、整数与浮点表达式、函数返回值 | [计算结果错误](cases/04_wrong_result/README.md) |
| 05 意外修改 | 金额字段被写成错误值 | watch 的旧值和新值、写入位置、调用栈 | [变量观察点](cases/05_watchpoint/README.md) |
| 06 异常退出 | 未捕获异常导致程序终止 | throw 时的业务栈、异常输入、后续终止路径 | [C++ 异常来源](cases/06_exception/README.md) |


## 2. 先完成一个案例

需要 Linux 环境中的 **g++、make、GDB**。进入项目根目录：

```bash
cd gdb-crash-practice
```

**本文和各案例里的相对路径命令，都在这个目录执行。** 不要切到某个 `cases/...` 子目录后直接照抄 `make build/...`。

### 编译并启动

以 01 空指针案例为例：

```bash
make build/01_segfault
gdb -q -nx --args build/01_segfault
```

`make` 会自动创建 `build/`。GDB 启动后，在 `(gdb)` 提示符输入：

```gdb
set pagination off
set debuginfod enabled off
set disable-randomization off
run
bt
info args
print order
```

本例应停在 `calculate_total` 的成员访问语句附近，收到 `SIGSEGV`。重点看：

1. `bt`：调用链如何从 `main` 经 `process_request` 到达这里。
2. `info args` / `print order`：参数 `order` 是否为 `0x0`。
3. 对照源码：当前语句正在通过这个指针访问对象成员。

继续按 [01 案例文档](cases/01_segfault/README.md) 检查调用者，并完成修复练习。结束这个由 GDB 启动的练习进程时输入：

```gdb
kill
quit
```

交互模式可能要求确认，按提示输入 `y`；如果目标已经退出，直接 `quit`。

### 编译全部案例

```bash
make
```

编译选项由 [Makefile](Makefile) 统一设置：

```text
-std=c++17 -O0 -g3 -fno-omit-frame-pointer -Wall -Wextra -Wpedantic -pthread
```

`-O0` 和调试信息让本套教学中的变量及单步流程更容易观察。真实优化程序可能出现内联、变量被优化掉、源码行跳跃等情况；分析真实故障时，应使用与故障二进制匹配的符号和源码。

## 3. 目录和文件分别负责什么

维护的项目文件如下；生成的编译产物单独放在 `build/`：

```text
gdb-guide/
├── README.md                 总入口、使用方法和命令速查
├── Makefile                  构建六个案例，提供 make verify
├── .gitignore                忽略 build 和 Python 缓存
├── cases/
│   ├── 01_segfault/
│   ├── 02_deadlock/
│   ├── 03_infinite_loop/
│   ├── 04_wrong_result/
│   ├── 05_watchpoint/
│   └── 06_exception/
└── scripts/
    └── verify.py             批量调用 GDB，汇总检查结果
```

每个案例目录都有四个文件：

| 文件 | 用途 | 什么时候看 |
|---|---|---|
| `main.cpp` | 最小故障源码 | 理解程序在做什么，对照实际执行位置 |
| `README.md` | 复现、GDB 排查、观察要点、原因与修复步骤 | 手动学习时的主要教程 |
| `inspect.gdb` | 可以交给 GDB 执行的命令和断言 | 手动练完后自动核对，或研究如何编写调试脚本 |
| `verification.txt` | 案例制作时保存的实测记录 | 对照关键变量和调用关系，具体地址及线程号可能不同 |

[scripts/verify.py](scripts/verify.py) 负责依次运行六个案例的 `inspect.gdb`、处理超时、清理自己启动的调试进程，并保存日志。它**不会自行编译 C++ 程序**，构建由 Makefile 负责。

## 4. 自动检查怎么用

### 一次构建并检查全部案例

```bash
make verify
```

执行顺序是：

```text
make 构建所需程序
    → scripts/verify.py
    → 各案例的 inspect.gdb
    → 输出 PASS / FAIL，保存 build/verification/ 日志
```

自动验证需要 **Python 3 和带 Python 支持的 GDB**。每个案例设置了 20 秒超时；验证完成或超时后，脚本会清理本次启动的调试进程。

**PASS 表示预设故障被成功复现，并且取到的证据符合预期。** 例如，01 检查到空指针和 SIGSEGV，才算通过。这不是“程序没有 bug”，也不是修复验收。

### 只检查一个案例

```bash
make build/01_segfault
gdb -q -nx -batch \
  -x cases/01_segfault/inspect.gdb \
  --args build/01_segfault
```

替换案例名称即可检查其他案例。通过 `make verify` 运行时，完整输出会写入 `build/verification/`；直接运行上面的单例命令时，输出显示在终端。

## 5. build 目录与修复练习

`build/` 是生成目录，首次编译时创建。它可能包含：

- 默认的六个故障程序，例如 `build/01_segfault`。
- 按案例文档编译的修复版程序，以及部分修复源码副本。
- `make verify` 生成的验证日志和自行保存的临时调试文件。

不需要其中的临时文件时，可以移除这个目录；**如果你在里面写了自己的修复代码，先保存想保留的改动。** 重新使用时：

| 操作 | 会生成什么 |
|---|---|
| `make` | 六个默认故障程序 |
| `make build/案例名` | 指定的一个故障程序 |
| `make verify` | 先构建所需程序，再生成本次验证日志 |

修复版、修复源码副本或自行保存的 core 文件，不会由 `make` 自动恢复。

各案例文档已经区分了故障版和修复版：

- **01、04**：复制源码到 `build/*_fixed.cpp`，修改副本并生成独立修复程序。
- **02、03、05、06**：使用 `-DFIX_BUG` 编译源码中提供的修复分支。

原始故障版用于反复练习；修复后的结果按对应文档检查。把修复版交给原来的故障检查脚本，可能会断言失败，因为预设故障已经消失。

## 6. GDB 停下以后，重点看什么

| 要回答的问题 | 常用命令 | 观察重点 |
|---|---|---|
| 为什么停了？ | 阅读停止消息 | 断点、观察点、SIGSEGV、SIGABRT 或手动中断 |
| 当前执行到哪里？ | `bt`、`list` | 当前函数、附近源码、上层调用路径 |
| 调用者传了什么？ | `frame N`、`up`、`info args` | 选对业务栈帧后检查参数 |
| 数据和类型是否正确？ | `info locals`、`print 表达式`、`whatis 变量` | 值、类型、边界条件、初始化时机 |
| 谁修改了这个值？ | `watch 表达式`、`bt` | 旧值、新值、写入者及其调用路径 |
| 线程在等什么？ | `info threads`、`thread apply all bt`、`thread N` | 持有与等待的资源，能否形成完整等待关系 |
| 异常从哪里抛出？ | `catch throw`、`bt` | 第一层业务函数和触发异常的输入 |
| 接下来走哪条分支？ | `next`、`step`、`continue` | 状态有没有按预期变化 |

其中 `N` 和表达式均需替换为本次现场的实际内容。不要只看“停在什么函数”，还要验证“为什么会走到这里”。

## 7. 几个容易混淆的地方

- **命令在哪里输入**：`bash` 代码块在 Linux 终端执行；`gdb` 代码块在调试器中输入。案例若显示 `(gdb)` 前缀，复制时省略前缀。
- **暂停和退出**：在 GDB 中 `run` 后按 Ctrl+C，是暂停目标并返回调试器；可继续检查卡死和死循环现场。
- **查看栈帧和执行程序**：`frame`、`up`、`down` 切换观察位置，不会倒退执行；`run` 从头启动，`continue` 从当前停止处继续。
- **线程编号**：`thread N` 使用 `info threads` 第一列的 GDB 编号，不是 Linux TID/LWP。
- **观察点的停止位置**：值通常已经被修改，源码箭头可能指向下一句；结合旧值、新值、附近代码和栈判断写入者。
- **异常和终止**：`catch throw` 命中不等于异常未捕获；要检查后续是否有处理器接住它。
- **等待和死锁**：看到 mutex / futex 等待栈还不足以证明死锁，02 案例会教你补齐持有关系与等待环。
- **多线程调度**：本练习使用正常多线程调度；不要在死锁案例运行前随意开启 `set scheduler-locking on`，否则可能阻止其他线程推进。

遇到变量不在当前上下文、系统库没有源码、地址或线程号与记录不一致时，先核对所选栈帧、变量作用域和本次输出；每个案例末尾也说明了相应局限。


## 许可说明
知识星球：“奔跑中cpp / c++” 所有，

阿甘微信：LLqueww

商业使用前请联系我方授权 一旦发现侵权行为，将依法追究法律责任

（对于公司法律事务已有对接律师，敬请告知）