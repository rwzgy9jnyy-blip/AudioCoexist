# AudioCoexist

A system-service audio coexistence tweak for **iOS 17.0 and a full RootHide jailbreak**. It hooks only `audiomxd`, applies the same session policy to all eligible clients, and requires no application-process injection or IPA modification.

[中文文档](README.md) · [Releases](https://github.com/rwzgy9jnyy-blip/AudioCoexist/releases) · [MIT license](LICENSE)

## Compatibility

Tested on an iPhone 14 Pro Max running iOS 17.0 with full RootHide system-process injection. The package requires `firmware >= 17.0, < 17.1`, `roothide` and `mobilesubstrate`; it contains arm64/arm64e binaries and uses RootHide's `iphoneos-arm64e` package architecture.

Sileo or Bootstrap alone does not establish system-process injection capability. Other OS versions, non-RootHide environments and iPhone 17 Pro Max are unverified. A standalone IPA on stock iOS cannot implement this system-service behavior.

## Policy

After checking runtime method signatures, the tweak overrides reads of `MXCoreSession`'s `mixesWithEveryone`, `interruptionStyle` and `allowMixableAudioWhileRecording`. It preserves the original stored session values and uses no per-application allowlist. The observed iOS 17.0 styles are `0x8` for exclusive audio and `0x10` for mixing; unrecognized priorities retain native behavior.

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

Host tests mock sessions and exercise eligibility, hook behavior and preservation of original values. They use AddressSanitizer, UndefinedBehaviorSanitizer and warnings as errors: **972 assertions** currently pass. GitHub Actions runs the same host tests; it does not validate physical-device audio.

Device feedback for 0.2.4 confirmed simultaneous Soda Music/Douyin playback, WeChat voice recording while music continued with WeChat remaining in the RootHide blacklist, and voice playback/app switching without the earlier pauses. Soda Music showed no unsafe-version prompt during the final retest. These observations do not establish compatibility with every app, Bluetooth/AirPlay, call transitions or long-term use.

## Source

`Server.mm` implements the system hooks, settings and diagnostics; `Policy.h` contains eligibility rules; `Control.m` implements the CLI; `AudioCoexistServer.plist` limits injection to audiomxd; `tests/server.mm` contains host tests.

Private-interface reference: [iOS 17 MediaExperience runtime headers](https://github.com/MTACS/iOS-17-Runtime-Headers/tree/main/PrivateFrameworks/MediaExperience.framework). No Apple private frameworks or third-party toolchain implementations are included.
