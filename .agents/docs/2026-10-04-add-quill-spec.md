# Quill 13.0.0 接入 mcpp 模块生态

日期：2026-10-04。状态：已按方案 A 实施，Linux GCC 与 LLVM/libc++ 验收通过；macOS、Windows 的运行结果由 PR CI 验证。

## 1. 范围与消费方式

包为 `odygrd.quill@13.0.0`，模块入口保持上游的 `import quill;`。复用正式发布的实验性模块，保留异步日志行为、公开 API 和内置 fmt。没有独立 compat 包、fork、自制 wrapper、额外 feature 或引擎改动。

```toml
[dependencies.odygrd]
quill = "13.0.0"
```

尚未发布到远程索引，本地使用时需要指向本 checkout：

```toml
[indices]
odygrd = { path = "/home/helan/community/mcpp-community/mcpp-index" }
```

消费者写 `import std; import quill;`。可通过 `quill::Frontend` 创建 sink/logger，使用无宏 API `quill::info(logger, "answer={}", 42)` 或运行时级别 `quill::log`。使用上游日志宏时额外写：

```cpp
#define QUILL_USE_MODULE
#include <quill/LogMacros.h>
```

随后可调用 `LOG_INFO` 或 `QUILL_LOG_INFO`。13.0.0 消费端显式定义 `QUILL_USE_MODULE`；不依赖包内 defines 自动传播。宏头在此模式下跳过普通类型头，并补充宏所需的 helper，不重复包含完整实现。`QUILL_MODULE`、`FMTQUILL_MODULE` 由上游模块自行定义，消费者无需设置。

两种 API 的行为不完全相同：上游 [`LogFunctions.h`](https://github.com/odygrd/quill/blob/v13.0.0/include/quill/LogFunctions.h) 说明无宏 API 的参数始终求值，存在运行时元数据处理，也不能像宏一样按编译期日志级别完全移除。接入不强制迁移原有宏用法，也不作性能等价承诺。

模块公开面以 13.0.0 的模块入口及它实际导出的声明为准；不承诺所有可选头都能通过 import 使用。没有新增 Syslog/Systemd/Android sink、Prometheus 示例或自定义 codec/formatter 导出。完整 Quill 文本头与模块混用、跨 DLL 共享后端不在此次验收范围内。

## 2. 固定的上游输入

- 上游：[odygrd/quill v13.0.0](https://github.com/odygrd/quill/releases/tag/v13.0.0)，MIT；保留根 LICENSE 和 bundled fmt 的声明。
- Tag commit：`eb802a37c7d585840324886a3d8648c9c2159952`。
- 归档：`https://github.com/odygrd/quill/archive/refs/tags/v13.0.0.tar.gz`。
- SHA-256：`88b4a1542125577a4d51cf444c51e34d63618c422ba6a4fa9bd23894b49d696b`；spec 调研时两次独立下载一致，实施中的真实下载通过包摘要校验。
- 解包根为 `quill-13.0.0/`。普通形态为头文件库，模块入口是 [`src/quill.cc`](https://github.com/odygrd/quill/blob/v13.0.0/src/quill.cc)，采用 CRLF。
- [`CMakeLists.txt`](https://github.com/odygrd/quill/blob/v13.0.0/CMakeLists.txt) 的 `QUILL_BUILD_MODULE` 标为 experimental，编译 `src/quill.cc` 并链接 `Threads::Threads`。
- 内置格式化库位于 `include/quill/bundled/fmt/`，使用 `fmtquill` 命名空间，无需依赖 `fmtlib.fmt` 或 `compat.fmt`。

调研时 GitHub Releases API 的 latest 为 13.0.0；实施时该 API 返回 403，改用 `git ls-remote --tags ... 'refs/tags/v13*'` 确认仍只有 `v13.0.0`。在线 latest 文档/master 出现的 13.1.0 内容未混入固定版本实现。

## 3. 接入方案与适配边界

采用内联 Form B 描述符 [`pkgs/o/odygrd.quill.lua`](../../pkgs/o/odygrd.quill.lua)：

| 字段 | 实现 |
|---|---|
| `namespace` / `name` | `odygrd` / `quill` |
| `language` / `import_std` | `c++23` / `false`；保留上游 global module fragment，消费者仍可导入 std |
| `modules` | `{ "quill" }` |
| `include_dirs` | `{ "*/include" }`，服务模块内部包含及消费端宏头 |
| `sources` | `{ "*/src/quill.cppm" }`，只编译一个入口 |
| `targets` / `deps` | `quill` lib / 空依赖 |
| Linux 链接 | `ldflags = { "-pthread" }` |
| 三平台下载 | 相同版本、归档和摘要，使用纯字符串 GLOBAL URL |

安装钩子检查源文件可读且恰有一条 `export module quill;`，以其内容生成同目录 `src/quill.cppm`。原 `.cc` 保留但不加入编译源集。507 个上游文件内容保持不变，适配仅作用于新增的 `.cppm`；读取后统一按 LF 匹配，兼容安装环境对 CRLF 的文本转换。

macOS ARM 的 PR CI 暴露两处上游模块入口问题，安装钩子执行两项精确替换，匹配次数不是一次即失败：

- x86 intrinsic 包含增加 x86 目标架构条件。Clang 在 ARM 上也能找到 `x86gprintrin.h`，仅靠 `__has_include` 会触发无效汇编约束和不存在的 x86 builtin。
- 在 global module fragment 中为 Apple 预包含 Mach 头，以及后端使用的 `unistd.h`、`fcntl.h`、`sys/file.h`、`sys/mman.h`、`sched.h`、`time.h` 和遗漏的 `<charconv>`。否则 Mach 类型、`timeval`、`timespec` 等在全局模块和 Quill 模块中重复归属，编译报错。

失败证据见 [PR CI 的 macOS job](https://github.com/mcpplibs/mcpp-index/actions/runs/37198494639/job/111425198293)。适配不修改 Quill 头文件、导出列表或日志实现。后续 CI 的 [macOS 系统头错误](https://github.com/mcpplibs/mcpp-index/actions/runs/37198733789/job/111425892513) 和 [Windows 换行匹配错误](https://github.com/mcpplibs/mcpp-index/actions/runs/37198733789/job/111425892875) 分别对应系统头补全和换行规范化；本地钩子检查已验证 CRLF/LF 生成相同结果，预期替换缺失时安装失败。

扩展名适配参考 [`fmtlib.fmt`](../../pkgs/f/fmtlib.fmt.lua)，避免 Clang 将 `.cc` 当普通翻译单元。实际 GCC、LLVM 构建图均只编译 `.cppm`，分别生成 `quill.gcm`、`quill.pcm`；未增加 `scan_overrides` 或完整生成式 wrapper。没有执行 CMake，`QUILL_BUILD_MODULE=ON` 不是本包的构建开关。

线程选项仅在 Linux 最终链接时传入，已检查两套构建图的 `ldflags`。不能只给模块或消费者一方增加影响 PCM 配置的 `-pthread` 编译选项：调研中的宿主 Clang 曾复现配置不一致，分开编译与链接后通过。当前 mcpp GCC/LLVM 构建无需额外线程编译选项。

上游对 MinGW 有 `ucrtbase` 分支，未将其泛化为所有 Windows 编译器的链接需求；Windows 的实际需求留待其 CI 工具链验证。未建立 CN 镜像，不声明猜测的地址；以后若增加镜像，须上传相同归档字节并核对摘要与可达性。

选择依据：复用模块及安装钩子参考 [Taskflow](2026-10-04-add-taskflow-spec.md)，保留上游模块名参考 [`khronos.vulkan-hpp`](../../pkgs/k/khronos.vulkan-hpp.lua)，内置 fmt 与 build/test 分别验证参考 [spdlog](2026-07-15-add-spdlog-plan.md)。普通头文件 `compat.quill` 无法提供所需 import；独立 Form A 适配仓会增加维护责任，目前均无必要。

## 4. 持久文件与测试契约

- 描述符：`pkgs/o/odygrd.quill.lua`。
- 测试成员：[`tests/examples/quill-module/mcpp.toml`](../../tests/examples/quill-module/mcpp.toml)，仅一条 odygrd 本地索引重定向；根 workspace 已登记。
- 测试入口：[`tests/quill.cpp`](../../tests/examples/quill-module/tests/quill.cpp)。
- 辅助 TU：[`src/log_worker.cpp`](../../tests/examples/quill-module/src/log_worker.cpp)。
- 中英文目录：`docs/descriptor-examples.md`、`docs/zh/descriptor-examples.md`。README 已链接这两份完整目录，无需改变其结构。

一个测试可执行文件、两个消费 TU，均使用 `import std; import quill;`，覆盖：

1. 主 TU 启动后端、创建 FileSink/logger；辅助 TU 在工作线程查询同名 logger，断言与主 TU 的指针相同。
2. 宏 `LOG_INFO` 输出整数和字符串；不包含任何 Quill 头的辅助 TU 通过 `quill::info` 输出 `std::vector<int>`，通过 `quill::log` 输出运行时级别记录。
3. 两个 TU 分别提交 Debug 日志，Info 阈值下断言它们均未输出。
4. producer 通过 `std::jthread` join，随后 flush/stop，再读回文件，断言三条有效消息的格式化内容和行数；不依赖时间戳、并发顺序或任意 sleep。
5. 每次创建独享临时目录；断言失败返回非零，异常写 stderr；结束后停止后端并清理目录。测试超时 30 秒。

## 5. 实际验证

宿主为 Linux x86_64，命令由 Bash 执行。使用临时解包的 **mcpp 2026.10.1.2**，与 `.github/workflows/validate.yml` 一致；PATH 中较新的 mcpp 未作为验收替代。通过进程级 `MCPP_HOME=/home/helan/.mcpp` 复用 GCC 16.1.0 和 LLVM 22.1.8，没有修改全局默认版本。

```sh
export MCPP=/tmp/quill-implementation/mcpp-2026.10.1.2-linux-x86_64/bin/mcpp
export MCPP_HOME=/home/helan/.mcpp
export MCPP_INDEX_MIRROR=GLOBAL
export MCPP_VENDORED_XLINGS=/tmp/quill-implementation/mcpp-2026.10.1.2-linux-x86_64/registry/bin/xlings
"$MCPP" xpkg parse --all-os pkgs/o/odygrd.quill.lua
"$MCPP" test -p quill-module --cache off --timeout 30
"$MCPP" test -p quill-module --toolchain llvm@22.1.8 --cache off --timeout 30
"$MCPP" test -p quill-module --timeout 30
```

| 检查 | 实际结果 |
|---|---|
| 隔离临时索引安装及 GCC/LLVM 测试 | 各 `1 passed; 0 failed` |
| 正式 workspace Linux GCC 16.1.0 | `1 passed; 0 failed`，19.78 秒，包含 6.9 秒下载 |
| 正式 workspace Linux LLVM 22.1.8 / libc++ | `1 passed; 0 failed`，6.03 秒 |
| 模块入口适配后的隔离冷安装及 GCC/LLVM | 各 `1 passed; 0 failed`，GCC 19.97 秒、LLVM 6.05 秒；507 个原始文件及生成入口的两处替换均已逐字节核对 |
| 正式 workspace GCC 增量 | `1 passed; 0 failed`，0.15 秒，构建 0.03 秒 |
| 独立普通消费工程 | `/tmp/quill-implementation/consumer` 指向正式 checkout，`mcpp run --cache off` 实际编译、链接、运行上述日志断言，退出 0 |
| 冷安装 | 隔离工程、正式 workspace、普通消费工程分别实际下载和安装；不将 `--cache off` 本身当作重装证据 |
| 安装文件比较 | 507 个上游文件内容不变，仅新增带两处模块入口适配的 `.cppm` |
| Lua 语法与三平台 xpkg 解析 | 通过，三平台均解析为 1 个 source、1 个 include 根 |
| 镜像 URL、包身份、保留 namespace | 新描述符通过对应 lint |
| 跨包引用、三平台版本一致性、重复版本 | 全仓对应 lint 通过 |
| CI 选择规则 | 描述符全名匹配唯一 `quill-module` 成员；新增 workspace 成员及测试路径也命中现有规则 |
| diff 空白检查 | 通过 |

临时工具、独立消费工程及日志位于 `/tmp/quill-implementation/`；原归档和宿主探测材料位于 `/tmp/quill-spec-G8O9Nt/`，不是长期源码依赖。

## 6. 未验证与发布边界

首次 PR CI 的 Windows 构建运行通过；macOS ARM 的失败由上述两处模块入口适配处理，最终验收以最新提交的 CI 结果为准。三平台描述符解析不等于运行验收。本节记录本地验证边界，跨平台结果以 PR CI 为准；未上传 CN 镜像。上游仍将模块标为实验性；本次不承诺所有 sink/codec/metrics、跨 DLL、完整文本头混用或性能指标。

后续三平台发布前应让 macOS/Windows 运行同一成员；若需要超出模块入口的小范围适配、改动日志实现或 mcpp 引擎，应先保留失败复现并重新审查范围，不以跳过平台或静默改成头文件包代替验收。
