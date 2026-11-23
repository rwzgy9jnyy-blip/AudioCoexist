# 修复记录 / Changelog

## 0.2.5 — 修复候选版 / Repair candidate

当前已完成源码测试、静态分析、并发检测及 RootHide 双架构打包；新构建尚未实机复测。

- **初始化并发**：修复 Hook 未全部就绪时已开始混音的问题。原方法指针原子发布，并在替换前准备回退；部分失败保持原行为，防止重复 Hook。
- **配置异常**：数组、字典等非法布尔值不再触发 `boolValue` 异常；CLI 和系统服务使用同一解析器。两个开关通过单个原子快照更新。
- **会话类型异常**：音频类别、模式及客户端标识类型不正确时保留原策略，避免向非字符串调用字符串方法。
- **诊断崩溃**：校验会话管理器及可选诊断方法的 ABI，处理异常返回类型和 Objective-C 异常；缺少属性输出 `-1`。
- **命令行**：多余参数返回用法错误（退出码 2）；补建缺失的配置目录；用文件锁保护读取、修改和原子替换，避免并发开关相互覆盖；失败时不报告成功。
- **音频线程与文件**：诊断写盘移出 Hook 调用线程；日志预算到限后不再递增；诊断文件使用 `0600`，拒绝日志/锁符号链接和非普通文件，快照采用原子替换。
- **测试覆盖**：移除将生产初始化、配置和诊断排除在宿主测试之外的分支。测试实际生产实现，包含完整策略真值表、安装失败、异常数据、诊断和独立 CLI 进程并发测试。ASan/UBSan 与 TSan 分别执行。
- **CI 调度**：改用 Intel macOS 测试机，避开默认 ARM 测试机容量不足造成的获取失败；仅在主分支推送、PR 或手动触发时运行，避免发布标签重复执行。

The 0.2.5 candidate hardens initialization, original-IMP publication, settings parsing, session type checks, diagnostic ABI handling, CLI argument validation/concurrent updates and diagnostic file I/O. Host tests now compile the production initialization/settings/diagnostic paths instead of excluding them. Physical-device retesting is still pending.

## 0.2.4

首次公开的系统服务版，仅作用于 `audiomxd`，没有 App 进程注入或逐 App 白名单。已有 iPhone 14 Pro Max / iOS 17.0 / RootHide 实机使用反馈，详见 README 的验证范围。
