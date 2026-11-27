# 修复记录 / Changelog

## 0.2.16 — 主播放控制权 / Primary playback control

- 将全体播放会话强制混音改为主次播放策略：首路原本独占的普通媒体播放保留系统原始策略，后续客户端进入混音，避免媒体控制资格丢失和后来的音源抢占控制目标。
- 通过原样转发的 `setIsPlayingOutput:` 观察真正出声；暂停仍保留主播放，以便继续键恢复音乐。
- 同一客户端的播放会话共享不持有会话对象的生命周期标记；切歌或辅助会话结束不会提前释放主播放，最后会话释放时自动清理。代际标记和并发保护避免旧会话清理影响新主播放。
- 保留原有录音混音及通话/安全等保护；仍只作用于 audiomxd，没有 App/耳机白名单、按键转发、轮询或定时扫描。
- ASan/UBSan、TSan 与 CLI 测试通过；2026-11-28 实机确认抖音前台连续刷视频时蓝牙始终控制汽水、双路出声，微信录音与回放时音乐继续且均正常。长期使用和全部路由尚未穷尽验证。

Keep the first ordinary, originally exclusive media client's native playback policy and mix later clients as secondary sources. Observe real output without changing setter arguments. Shared, non-owning session-lifetime leases preserve the primary across pause/resume, track replacement and auxiliary sessions, with generation and concurrency protection. No app hooks, device allowlists, command forwarding or polling are added. Host tests pass. On November 28, 2026, the tester confirmed Bluetooth continued to control Soda while browsing several Douyin videos with both sources audible; WeChat recording and voice playback also worked while music continued. Long-term operation and every route remain unverified.

## 0.2.6 — 减少重复会话查询 / Hot-path efficiency

- 系统本来已返回允许混音、允许录音共处或混音中断值时，直接保留原结果，不再读取整套会话元数据。
- 复用已经读取的中断值和音频类别；保护会话提前返回，预先保存方法 selector，减少重复查询。
- 不缓存会话资格；语音聊天、通话、安全和其他保护状态变化后仍即时使用当前规则。没有新增轮询、定时器或 App 注入。
- 增加 1000 轮原生已允许分支检查及属性读取计数测试；ASan/UBSan、TSan 和独立 CLI 测试通过。整机续航改善幅度尚未测得。

Native values that already permit mixing now bypass redundant eligibility queries. Changed paths reuse the raw interruption style and parsed category; mutable eligibility is never cached. Tests cover getter-call counts and immediate transitions to protected modes. No polling or timers were added. Battery-life improvement has not been quantified.

## 0.2.5 — 修复候选版 / Repair candidate

已完成源码测试、静态分析、并发检测、RootHide 双架构打包及基础实机复测。2026-11-24 在 iPhone 14 Pro Max / iOS 17.0 / RootHide 上，用户确认汽水与抖音同时出声、微信录音和回放正常，测试中暂未出现“不安全”提示。微信黑名单和其他插件保持原状。长期稳定性仍在观察，暂保留候选版标记。

- **初始化并发**：修复 Hook 未全部就绪时已开始混音的问题。原方法指针原子发布，并在替换前准备回退；部分失败保持原行为，防止重复 Hook。
- **配置异常**：数组、字典等非法布尔值不再触发 `boolValue` 异常；CLI 和系统服务使用同一解析器。两个开关通过单个原子快照更新。
- **会话类型异常**：音频类别、模式及客户端标识类型不正确时保留原策略，避免向非字符串调用字符串方法。
- **诊断崩溃**：校验会话管理器及可选诊断方法的 ABI，处理异常返回类型和 Objective-C 异常；缺少属性输出 `-1`。
- **命令行**：多余参数返回用法错误（退出码 2）；补建缺失的配置目录；用文件锁保护读取、修改和原子替换，避免并发开关相互覆盖；失败时不报告成功。
- **音频线程与文件**：诊断写盘移出 Hook 调用线程；日志预算到限后不再递增；诊断文件使用 `0600`，拒绝日志/锁符号链接和非普通文件，快照采用原子替换。
- **测试覆盖**：移除将生产初始化、配置和诊断排除在宿主测试之外的分支。测试实际生产实现，包含完整策略真值表、安装失败、异常数据、诊断和独立 CLI 进程并发测试。ASan/UBSan 与 TSan 分别执行。
- **CI 调度**：改用 Intel macOS 测试机，避开默认 ARM 测试机容量不足造成的获取失败；仅在主分支推送、PR 或手动触发时运行，避免发布标签重复执行。

The 0.2.5 candidate hardens initialization, original-IMP publication, settings parsing, session type checks, diagnostic ABI handling, CLI argument validation/concurrent updates and diagnostic file I/O. Host tests now compile the production initialization/settings/diagnostic paths instead of excluding them. A basic iPhone 14 Pro Max / iOS 17.0 / RootHide retest passed on November 24, 2026: simultaneous Soda Music/Douyin sound, normal WeChat recording/playback and no unsafe-version prompt during the test so far. Long-term observation continues; the prerelease designation is retained.

## 0.2.4

首次公开的系统服务版，仅作用于 `audiomxd`，没有 App 进程注入或逐 App 白名单。已有 iPhone 14 Pro Max / iOS 17.0 / RootHide 实机使用反馈，详见 README 的验证范围。
