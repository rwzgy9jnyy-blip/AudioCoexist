# AudioCoexist

A system-service audio coexistence tweak for **iOS 17.0 and a full RootHide jailbreak**. It hooks only `audiomxd`, applies the same session policy to all eligible clients, and requires no application-process injection or IPA modification.

[中文文档](README.md) · [0.2.16 candidate download](https://github.com/rwzgy9jnyy-blip/AudioCoexist/releases/tag/v0.2.16) · [MIT license](LICENSE)

This source is the **0.2.16 Bluetooth-control repair candidate**, addressing loss of Now Playing eligibility and competing control targets under global mixing while retaining the 0.2.6 query optimizations. Host tests, concurrency checks and RootHide builds pass. The previously published [0.2.5 candidate](https://github.com/rwzgy9jnyy-blip/AudioCoexist/releases/tag/v0.2.5) and original 0.2.4 remain available. [Changelog](CHANGELOG.md)

Native values that already allow mixing bypass eligibility reads; changed paths reuse the raw interruption style and category. Mutable eligibility is never cached. There is no polling timer; session scans remain explicit `dump` requests. Reduced call overhead is not a measured whole-device battery-life percentage.

## Compatibility

Tested on an iPhone 14 Pro Max running iOS 17.0 with full RootHide system-process injection. The package requires `firmware >= 17.0, < 17.1`, `roothide` and `mobilesubstrate`; it contains arm64/arm64e binaries and uses RootHide's `iphoneos-arm64e` package architecture.

Sileo or Bootstrap alone does not establish system-process injection capability. Other OS versions, non-RootHide environments and iPhone 17 Pro Max are unverified. A standalone IPA on stock iOS cannot implement this system-service behavior.

## Policy

After checking runtime method signatures, the tweak overrides reads of `MXCoreSession`'s `mixesWithEveryone`, `interruptionStyle` and `allowMixableAudioWhileRecording`, and observes `setIsPlayingOutput:` while forwarding its arguments unchanged. It preserves the original stored session values and uses no per-application allowlist. The observed iOS 17.0 styles are `0x8` for exclusive audio and `0x10` for mixing; unrecognized priorities retain native behavior.

Mixing activates only after all four hooks are ready. A partial installation remains inactive and preserves native behavior.

The first originally exclusive ordinary media client to start actual output and opt into media controls becomes the primary. Its mixing and interruption values remain native; later clients mix in as secondary sources. Bluetooth, lock-screen and Control Center commands follow the native command chain. Starting music before video keeps music as the primary.

Pausing retains the role so Bluetooth play can resume the same primary. Track changes and auxiliary playback sessions from that client share the role; it expires when the client's last associated playback session is released. Close the primary player before starting another source to change the primary. Selection uses session state and process identity, with no application or headset allowlist, periodic scans, polling or command forwarding.

Recognized playback categories are MediaPlayback, Audio/Video, AmbientSound and SoloAmbientSound. Record and PlayAndRecord variants can mix in Default mode when recording coexistence is enabled. Playback also accepts MoviePlayback and SpokenAudio modes. Default, long-form audio and long-form video sharing policies are eligible; independent routes are preserved.

Phone calls, voice/video chat modes, the assistant, hardware safety, car and SharePlay call sessions retain their original policy, as do unknown categories and modes. Global scope means a common policy inside the system service, not unconditional mixing for every special session. Apps that voluntarily pause themselves are not guaranteed to keep playing.

## Install, control and remove

Install the release `.deb` using Sileo in a compatible RootHide environment, then restart the audio service as root on the device:

```sh
launchctl kickstart -k user/501/com.apple.audiomxd
```

This briefly interrupts audio; perform it outside calls, recording or important playback. The package does not restart audio services or SpringBoard automatically.

The following commands run as root on the device:

```sh
audio-coexist status
audio-coexist on
audio-coexist off
audio-coexist record-on
audio-coexist record-off
audio-coexist dump
```

Both switches default to enabled. `status` reports configuration, not successful runtime loading. Settings are delivered using Darwin notifications; existing sessions may need to restart playback. `dump` requests a snapshot asynchronously; inspect the file to confirm a response.

Paths below are relative to the RootHide jailbreak root:

- `/var/mobile/Library/Preferences/com.codex.audiocoexistserver.plist`: Enabled and Recording settings.
- `/tmp/AudioCoexistServer.runtime`: load marker and limited policy-change logging.
- `/tmp/AudioCoexistServer.sessions`: session metadata requested by `dump`.

Diagnostics contain application identifiers and session attributes, not recorded audio. Redact private information before sharing them.

In 0.2.5 diagnostics use a separate queue and `0600` files; read them as root. Missing diagnostic properties are reported as `-1`; incompatible interfaces produce `unavailable`. Configuration accepts numbers/booleans and true/false, yes/no or 1/0 strings; invalid types use defaults. CLI writes use a file lock and atomic replacement to preserve concurrent updates.

To uninstall, remove the package in Sileo and restart `audiomxd` using the command above. Already-loaded code and existing session state can remain until the service restarts.

## Build and test

Requires macOS, full Xcode with an iPhoneOS SDK, a RootHide-compatible Theos setup, ldid and Debian packaging tools. See [RootHide Developer](https://github.com/roothide/Developer) for toolchain configuration; dependencies are not vendored.

```sh
git clone https://github.com/rwzgy9jnyy-blip/AudioCoexist.git
cd AudioCoexist
bash test.sh
export THEOS=/path/to/theos-roothide
bash build.sh
```

Set `DEVELOPER_DIR` if needed; otherwise the build uses `xcode-select -p`. The build cleans before packaging so entitlement changes are re-signed. Packages appear in `packages/`. Preserve both packaging symlinks, including `.jbroot`. The CLI's four RootHide-required entitlements are declared in `Entitlements.plist`.

Host tests compile the production code, replacing only RootHide paths, Substrate method replacement and private-class lookup. Initialization, settings and diagnostics are included. They cover the policy truth table, 1,000 native-permission fast-path iterations, getter-call counts and immediate protected-mode transitions, plus **5 CLI integration tests using separate processes**, including 20 concurrent update rounds, malformed settings, incompatible diagnostic interfaces and partial hook failure.

The default run uses AddressSanitizer, UndefinedBehaviorSanitizer and warnings as errors. Run `ASC_SANITIZERS=thread bash test.sh` for ThreadSanitizer; GitHub Actions runs both. Test doubles do not establish actual Substrate/ElleKit loading, device threading rules or physical-device audio behavior.

**0.2.16 basic device retest, November 28, 2026:** iPhone 14 Pro Max / iOS 17.0 / RootHide. Host ASan/UBSan, TSan and build checks pass; the audio service remained running. The tester started Soda Music before Douyin and browsed several videos with Douyin in the foreground: Bluetooth pause/resume and track switching continued to control Soda, with both sources audible after resuming. WeChat recording followed by cancellation, and playback of an existing voice message, also worked while music continued. WeChat's blacklist and other tweaks were preserved.

Regression checks cover primary/secondary playback, pause/resume, replacement and auxiliary sessions, last-session cleanup and concurrent claims. Feedback covers these scenarios and this test period; every device, route and long-term operation remain unverified, so the candidate designation is retained.

**0.2.5 basic device retest, November 24, 2026:** iPhone 14 Pro Max / iOS 17.0 / RootHide. Installation checks confirmed the new version loaded, hooks ran and session diagnostics completed; WeChat's RootHide blacklist setting and other tweaks were preserved. The tester confirmed simultaneous Soda Music/Douyin sound, normal WeChat recording and voice playback, and no unsafe-version prompt during this test so far. This feedback covers only these scenarios and this test period. Long-term behavior, every app and every route remain unproven, so 0.2.5 retains its prerelease designation.

Earlier 0.2.4 feedback confirmed simultaneous Soda Music/Douyin playback, WeChat voice recording while music continued with WeChat remaining in the RootHide blacklist, and voice playback/app switching without the earlier pauses. Soda Music showed no unsafe-version prompt during its final retest. These observations do not establish compatibility with every app, Bluetooth/AirPlay, call transitions or long-term use.

## Source

`Server.mm` implements the system hooks and diagnostics; `Policy.h` contains eligibility rules; `Settings.h` shares configuration parsing; `FileIO.h` handles atomic writes and file checks; `Control.m` implements the CLI; `AudioCoexistServer.plist` limits injection to audiomxd; `tests/` contains server and CLI tests.

Private-interface reference: [iOS 17 MediaExperience runtime headers](https://github.com/MTACS/iOS-17-Runtime-Headers/tree/main/PrivateFrameworks/MediaExperience.framework). No Apple private frameworks or third-party toolchain implementations are included.
