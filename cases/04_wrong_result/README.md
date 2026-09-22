# 04：程序正常退出，但平均值算错

[返回练习首页](../../README.md) · [案例源码](main.cpp) · [GDB 自动脚本](inspect.gdb)

这个案例练习在没有崩溃的情况下定位错误结果。输入固定为 `10、11、12、14`，总和 `47`，正确平均值是 `11.75`；故障程序输出 `actual=11 expected=11.75 match=false`，并正常退出。

缺陷在 `divide_total(int total, int count)`：`return total / count;` 先进行整数除法，再把整数结果转换成函数返回类型 `double`。返回类型不会让前面的除法自动变成浮点除法。

## 编译与复现

以下是 **Shell 命令**：

```bash
mkdir -p build
g++ -std=c++17 -O0 -g3 -fno-omit-frame-pointer \
    -Wall -Wextra -Wpedantic -pthread \
    cases/04_wrong_result/main.cpp -o build/04_wrong_result
./build/04_wrong_result
gdb -q -nx --args build/04_wrong_result
```

也可以使用根目录的 `make` 构建所有案例。

预期首次直接运行输出：

```text
actual=11 expected=11.75 match=false
```

这类错误不会因为程序退出码为 `0` 而自动被发现，检查必须包含结果断言。

## 一步步观察

下方 `(gdb)` 是提示符，不需要输入。

1. 在计算结果和展示结果的两端设置函数断点。

   ```text
   (gdb) set pagination off
   (gdb) set debuginfod enabled off
   (gdb) break divide_total
   (gdb) break display_result
   (gdb) run
   ```

   首先停在 `divide_total`。这里能在最终除法之前检查输入，另一个断点用来确认错误值确实传到了输出层。

2. 检查数值和类型，区分输入错误与计算规则错误。

   ```text
   (gdb) info args
   (gdb) whatis total
   (gdb) whatis count
   (gdb) print total / count
   (gdb) print (double)total / count
   (gdb) list divide_total
   ```

   应看到 `total=47`、`count=4`，两个变量都是 `int`。同样的输入，整数表达式结果为 `11`，先转换一个操作数后的浮点表达式结果为 `11.75`。这些 `print` 表达式只计算并展示值，没有修改程序变量。

3. 沿栈检查实际输入。

   ```text
   (gdb) bt
   (gdb) frame 1
   (gdb) info locals
   (gdb) frame 2
   (gdb) print values
   (gdb) frame 0
   ```

   本例的栈为 `divide_total -> average_score -> main`。在 `average_score` 中应看到累计和 `total=47`；在 `main` 中应看到数组 `{10, 11, 12, 14}`。随后返回 `frame 0`，让下一步 `finish` 针对 `divide_total`。帧编号要以当前 `bt` 为依据。

4. 跟踪函数实际返回的值，再看接收方。

   ```text
   (gdb) finish
   (gdb) continue
   (gdb) print actual
   ```

   `finish` 运行当前函数直到返回，应报告返回值 `11`；`continue` 运行到 `display_result` 的断点，其参数 `actual` 也为 `11`。这证明丢失的小数在输出之前已经丢失，缺陷并非输出格式造成。

   断点停在 `display_result` 入口时，局部常量 `expected` 可能尚未初始化，不要直接把此时的局部变量显示当成有效值。这里检查已经传入的参数 `actual` 即可。

5. 运行到正常退出。

   ```text
   (gdb) continue
   (gdb) print $_exitcode
   (gdb) quit
   ```

   应看到错误输出、`exited normally` 和退出码 `0`。程序正常退出与计算结果正确是两件独立的事。

## 从现场证据推到原因

| 证据 | 能得出的判断 |
| --- | --- |
| 原数组正确，总和 `47`、个数 `4` 正确 | 本例不是输入或求和阶段出错 |
| 两个除法操作数都是 `int` | `/` 按整数除法规则计算；本例正数结果去掉小数部分 |
| GDB 中 `total / count=11`，`(double)total / count=11.75` | 小数丢失发生在除法，类型转换的位置决定结果 |
| 实际函数返回值和 `display_result` 参数均为 `11` | 不是 `std::cout` 格式化隐藏了仍然存在的小数 |

不要用 `static_cast<double>(total / count)` 修复：它把已经截去小数的 `11` 转成 `11.0`，仍然得不到 `11.75`。

## 最小修复与检查

先在 build 下创建修复副本，保留原故障源码：

```bash
mkdir -p build
cp cases/04_wrong_result/main.cpp build/04_wrong_result_fixed.cpp
```

编辑 `build/04_wrong_result_fixed.cpp`，仅修改返回表达式：

```cpp
double divide_total(int total, int count) {
    return static_cast<double>(total) / count;
}
```

先把一个操作数转成 `double`，除法才会按浮点规则进行。重新编译并运行：

```bash
g++ -std=c++17 -O0 -g3 -fno-omit-frame-pointer \
    -Wall -Wextra -Wpedantic -pthread \
    build/04_wrong_result_fixed.cpp -o build/04_wrong_result_fixed
./build/04_wrong_result_fixed
```

预期输出 `actual=11.75 expected=11.75 match=true`，正常退出。修复后重新进行上述 GDB 观察，`finish` 返回值与 `actual` 都应为 `11.75`。

本目录仍保留缺陷；实际核查在临时副本中应用此修复并得到了上述正确输出。

## 自动核查

以下脚本验证**故障仍可按设计复现**：

```bash
gdb -q -nx -batch -x cases/04_wrong_result/inspect.gdb --args build/04_wrong_result
```

脚本断言原始输入、整数与浮点表达式结果、错误的实参 `actual=11` 和正常退出码，最后打印 `[PASS] 04_wrong_result`。这个 PASS 不是修复验收；把源码修好后，原脚本理应不再通过。

实际核查输出见 [verification.txt](verification.txt)，非空地址使用 `<address>` 占位。

