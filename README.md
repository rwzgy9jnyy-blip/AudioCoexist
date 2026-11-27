# AudioCoexist · 全局音频共处

[![Host tests](https://github.com/rwzgy9jnyy-blip/AudioCoexist/actions/workflows/test.yml/badge.svg)](https://github.com/rwzgy9jnyy-blip/AudioCoexist/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

在 iOS 系统音频服务 `audiomxd` 中调整会话混音策略，让音乐、短视频、普通录音及录音回放可以共处。

**仅作用于系统音频服务，不向 App 进程注入代码。** 所有符合条件的会话使用同一套规则，没有逐 App 白名单，也不需要修改 IPA 或 RootHide 黑名单。普通未越狱设备上的独立 IPA 无法实现这个系统级功能。

[下载 0.2.16 候选版](https://github.com/rwzgy9jnyy-blip/AudioCoexist/releases/tag/v0.2.16) · [English](README.en.md)

本次源码为 **0.2.16 蓝牙控制修复候选版**，修正全局混音导致媒体控制资格丢失和控制目标争抢的问题，保留 0.2.6 的查询开销优化。已通过宿主机测试、并发检测与 RootHide 构建。此前发布的 [0.2.5 候选包](https://github.com/rwzgy9jnyy-blip/AudioCoexist/releases/tag/v0.2.5) 和 0.2.4 安装包仍保留。[修复记录](CHANGELOG.md)

0.2.6 对系统本来已允许的返回值直接保留，复用中断值和类别，保护会话提前返回；不缓存可变会话资格。插件没有常驻轮询或定时器，诊断扫描仍只在主动 `dump` 时运行。此项减少调用开销，尚不能换算为整机省电百分比。

## 兼容范围

| 项目 | 当前范围 |
| --- | --- |
| 实机验证 | iPhone 14 Pro Max，iOS 17.0，RootHide 完整越狱环境 |
| 软件包依赖 | iOS `>= 17.0, < 17.1`；RootHide；兼容 Substrate 的 Hook 框架 |
| 注入目标 | 仅 `audiomxd`；需要系统进程注入能力 |
| 构建架构 / 包架构 | `arm64` + `arm64e` / RootHide `iphoneos-arm64e` |

仅有 Sileo 或 Bootstrap 并不证明具备系统进程注入能力。其他系统版本、非 RootHide 越狱及 iPhone 17 Pro Max 未验证，不提供通用兼容承诺。

## 工作方式

插件检查 `MXCoreSession` 所需方法的运行时签名，然后 Hook 三个读取方法，并观察播放状态 setter；四项全部就绪才启用策略，部分安装失败时保持原行为：

- `mixesWithEveryone`
- `interruptionStyle`
- `allowMixableAudioWhileRecording`
- `setIsPlayingOutput:`（原样转发参数，仅观察开始出声）

对符合条件的次路会话返回允许混音的策略，不改写其原始存储值。iOS 17.0 实测中断值 `0x8` 对应独占，`0x10` 对应混音；未知优先级保持系统原行为。

首次开始出声、允许媒体控制且原本独占的普通媒体客户端成为主播放。主播放保留原生混音和中断策略，后来的客户端进入混音；蓝牙、锁屏与控制中心继续走系统原有命令链路，视频不会因共处而被额外赋予媒体控制资格。先播放音乐，再打开视频时，音乐持有主播放角色。

暂停不释放角色，以便蓝牙继续键恢复同一主播放；同一客户端切歌或创建辅助播放会话时共享角色。该客户端最后一个关联播放会话释放后，角色自动结束，下一路开始播放时可接管。切换主播放器时可退出原主播放 App 后再播放新音源。角色由系统会话与进程标识确定，没有 App/耳机名称白名单。没有新增轮询、全会话定时扫描或按键转发。

播放支持 `MediaPlayback`、`Audio/Video`、`AmbientSound`、`SoloAmbientSound`，录音支持 `Record`、`PlayAndRecord*`。默认模式适用；播放另支持 `MoviePlayback`、`SpokenAudio`。媒体共享策略接受默认、长音频、长视频，独立路由不强制修改。

通话、语音/视频聊天模式、语音助手、硬件安全、车载和 SharePlay 通话会话，以及未知类别或模式，保留系统策略。这里的“全局”指系统服务中的统一规则，不代表强制所有特殊会话同时出声；App 主动暂停播放的行为也不保证能覆盖。

## 安装与卸载

1. 从 [Releases](https://github.com/rwzgy9jnyy-blip/AudioCoexist/releases) 下载 `.deb`，可用同页的 `SHA256SUMS.txt` 校验。
2. 在兼容的 RootHide 环境中，用 Sileo 安装本地软件包。
3. 在设备上以 root 重启系统音频服务，使插件加载：

   ```sh
   launchctl kickstart -k user/501/com.apple.audiomxd
   ```

重启音频服务会短暂中断声音，请在没有通话、录音或重要播放时执行。软件包不自动重启音频服务或 SpringBoard。

卸载时在 Sileo 移除“音频共处 · 系统服务版”，随后同样重启 `audiomxd`。已经加载的代码和现有会话状态可能持续到服务重启，不能只凭卸载后仍能混音判断插件未移除。

## 控制

设备终端或 SSH 中以 root 运行：

```sh
audio-coexist status      # 显示配置开关，不代表运行时 Hook 已加载
audio-coexist on          # 开启（默认）
audio-coexist off         # 关闭
audio-coexist record-on   # 允许普通录音会话共处（默认）
audio-coexist record-off  # 关闭录音共处
audio-coexist dump        # 请求会话诊断快照
```

配置通过 Darwin 通知传给音频服务。切换开关后，已有会话可能需要重新开始播放；需要彻底清理现有状态时重启音频服务。

以下路径均相对于 RootHide 的越狱根目录：

| 路径 | 用途 |
| --- | --- |
| `/var/mobile/Library/Preferences/com.codex.audiocoexistserver.plist` | `Enabled`、`Recording` 配置；缺省均开启 |
| `/tmp/AudioCoexistServer.runtime` | Hook 加载标记及有限条策略修改日志 |
| `/tmp/AudioCoexistServer.sessions` | `dump` 生成的会话元数据 |

配置支持布尔值、数字及 `true/false`、`yes/no`、`1/0` 字符串，异常类型按缺省值处理。命令行使用文件锁和原子替换，避免同时修改开关时丢失更新。

诊断只记录 App 标识和音频会话属性，不采集录音内容；日志可能含使用中的 App 信息，提交 Issue 前请自行删去私密信息。0.2.5 将诊断写盘移至独立队列，文件权限收紧至 `0600`；使用 root 读取。`dump` 返回只表示请求已发出，需查看快照确认服务响应；不可用的诊断属性标为 `-1`，接口不兼容时输出 `unavailable`。

## 构建

需要 macOS、完整 Xcode 和 iPhoneOS SDK、RootHide 兼容的 Theos、`ldid`、Debian 打包工具。按照 [RootHide 开发文档](https://github.com/roothide/Developer) 配置工具链；依赖不随本仓库分发。

```sh
git clone https://github.com/rwzgy9jnyy-blip/AudioCoexist.git
cd AudioCoexist
bash test.sh
export THEOS=/path/to/theos-roothide
bash build.sh
```

安装了多个 Xcode 时，可先设置 `DEVELOPER_DIR`。`build.sh` 默认采用 `xcode-select -p` 选中的开发目录，先清理再打包，确保命令行工具的 entitlements 重新签入。产物位于 `packages/`。

命令行工具使用 RootHide 要求的四项权限，见 [Entitlements.plist](Entitlements.plist)；RootHide 定位使用的 `.jbroot` 以及命令行入口均以符号链接保存，请保留其类型。

## 验证范围

`bash test.sh` 在 macOS 上编译实际生产代码，仅用测试替身替换 RootHide 路径、Substrate 方法替换和私有类查找，不再排除初始化、配置及诊断代码。覆盖策略真值表、1000 轮快速分支回归及属性读取计数，以及 **5 组独立 CLI 进程集成测试**，包括 20 轮并发修改、异常配置、诊断 ABI 不匹配和部分 Hook 失败。模式和通话保护切换后的规则会重新判断。

默认启用 AddressSanitizer、UndefinedBehaviorSanitizer 和警告即错误；另可运行 `ASC_SANITIZERS=thread bash test.sh` 检测并发。GitHub Actions 执行两种检测。测试替身不能证明真实 Substrate/ElleKit 加载、设备线程规则或实际音频行为；实机验证仍单独进行。

**0.2.16 基础实机复测（2026-11-28）**：iPhone 14 Pro Max / iOS 17.0 / RootHide。宿主机 ASan/UBSan、TSan 与构建检查通过，系统服务稳定运行。测试者确认：先播放汽水，再进入抖音连续滑动多个视频，蓝牙暂停、继续和切歌始终控制汽水，恢复播放后双路声音正常；微信录音取消及已有语音回放时音乐继续，录音和回放均正常。微信黑名单和其他插件保持原状。

主次播放、暂停恢复、切歌/辅助会话替换、最后会话释放和并发争抢有宿主回归检查。这次实机反馈只覆盖上述场景和时段；全部设备、路由及长期运行未穷尽验证，保留候选版标记。

**0.2.5 基础实机复测（2026-11-24）**：iPhone 14 Pro Max / iOS 17.0 / RootHide。安装后已确认新版本加载、Hook 执行和诊断快照正常；微信保持原有 RootHide 黑名单，其他插件保持原状。用户确认：

- 汽水音乐和抖音能够同时出声。
- 微信录音和录音回放正常。
- 本次测试暂未出现汽水音乐“不安全”提示。

这次反馈只覆盖上述场景和测试时段，尚不能证明长期不会再次提示或所有 App、路由均兼容；0.2.5 暂保留候选版标记。

0.2.4 的原实机使用反馈：

- 汽水音乐播放时刷抖音，两边同时有声。
- 微信保持 RootHide 黑名单时，按住语音录音，音乐继续且录音正常。
- 录音回放及 App 切换复测未再暂停音乐，复测时汽水音乐未提示“不安全”。

尚未穷尽所有 App、蓝牙/AirPlay、通话切换与长期稳定性。此版本依赖 iOS 私有接口，不应直接扩大系统版本范围而不做实机验证。

## 源码与参考

| 文件 | 用途 |
| --- | --- |
| [Server.mm](Server.mm) | 系统服务 Hook、运行时检查、配置和诊断 |
| [Policy.h](Policy.h) | 会话资格规则 |
| [Settings.h](Settings.h) | 共用配置解析与开关快照 |
| [FileIO.h](FileIO.h) | 原子写入与文件类型、权限处理 |
| [Control.m](Control.m) | 设备端命令行控制 |
| [AudioCoexistServer.plist](AudioCoexistServer.plist) | 仅 `audiomxd` 的注入过滤器 |
| [tests/server.mm](tests/server.mm) | 宿主机策略与 Hook 测试 |

接口与工具链参考：[iOS 17 MediaExperience 运行时头文件](https://github.com/MTACS/iOS-17-Runtime-Headers/tree/main/PrivateFrameworks/MediaExperience.framework)、[RootHide Developer](https://github.com/roothide/Developer)。本仓库未附带 Apple 私有框架或第三方工具链实现。

## 许可证

[MIT](LICENSE)。
