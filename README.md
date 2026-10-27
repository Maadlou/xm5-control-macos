# XM5 Control for macOS

A native SwiftUI menu-bar controller for Sony WH-1000XM5 and WH-1000XM6 headphones.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Compatibility

| Device | Implementation | Hardware verification |
|---|---|---|
| WH-1000XM5 | Existing six-value EQ and controls preserved; automated regression coverage | Re-run the manual checklist before release |
| WH-1000XM6 | Model-aware discovery, ANC/ambient, battery, and ten-band EQ implemented | Pending local device and firmware testing |
| WF-1000XM5 | Legacy discovery retained | No new hardware certification |
| WF-1000XM6 | Not supported by this change | Not tested |

Automated tests use reference-derived packets and simulated devices. They do not establish compatibility with every firmware. Follow the [manual hardware checklist](docs/testing/xm5-xm6-manual-checklist.md) on each model before marking a release verified. The existing v0.1.0 download predates XM6 support; use a build of this branch for these checks.

## Current features

- Finds supported paired headphones through macOS IOBluetooth and opens Sony's `Serial HPC` service over RFCOMM.
- Validates the MDR v2 handshake and reported capabilities, with bounded opening/sync timeouts.
- Reads live noise-control state and notifications, and offers supported Off, Noise Cancelling, and Ambient modes.
- Controls ambient level and Focus on Voice when advertised; includes Focus, Office, and Aware presets where supported.
- Reads battery/charging state and firmware; shows battery or listening mode in the macOS menu bar.
- Preserves XM5's Off, Bright, Excited, Mellow, Relaxed, Vocal, Treble Boost, Bass Boost, and Speech presets.
- Offers the XM6-native Off, Heavy, Clear, Hard, and Soft preset catalogue.
- Provides an XM5 custom EQ editor with Clear Bass and five bands (-10...10), or an XM6 ten-band editor (-6...6).
- Stores local named profiles and drafts separately for each EQ layout. Existing XM5 profile names, IDs, curves, and preferences survive migration; original legacy storage remains untouched.
- Supports explicitly labelled offline EQ editing and saving. Incompatible profiles are excluded from both preset pickers; no automatic cross-layout conversion occurs.
- Debounces edits and confirms device writes through readback. A transport ACK alone does not report success; unconfirmed changes show an error.
- Provides the permission-free global `⌥⌘A` shortcut to toggle Noise Cancelling and Ambient mode.
- Supports launch at login, optional automatic control-link reconnection, capped retry backoff, and periodic state synchronization.
- Distinguishes Bluetooth audio from Sony control-link availability and provides copyable model, protocol, capability, firmware, sync, and error diagnostics.
- Keeps the existing XM5 artwork and uses a neutral headphone symbol for XM6.

## Device selection

The app prefers a connected supported device over a disconnected paired device. It keeps the current device while that device remains connected; remaining ties use Bluetooth address order. To switch when both models are connected, disconnect the current device in macOS Bluetooth settings. Simultaneous control and an explicit device picker are not included.

Discovery recognizes the original WH/WF model tokens and retains the old `1000XM5` name substring fallback. A renamed XM6 with no recognizable model token will not be discovered.

## Development

Open `XM5 Control.xcodeproj` in Xcode 26 or newer. The app targets macOS 14 or newer and uses Swift 6.

The development bundle identifier remains `local.xm5control`. Replace it with a globally unique identifier before signing or distribution. The app name, module identity, shortcut registration, and preference domain are unchanged by XM6 support.

The headphones must be paired and powered on. Only one process can own the Sony RFCOMM channel at a time, so quit other Sony-control utilities while testing. A missing or unsupported EQ response disables EQ independently of working noise controls.

Active headphone settings can be cross-checked with Sony Sound Connect. Named Mac profiles remain local; applying a profile sends its curve, not its custom name, to the headphones. User EQ slots are not exposed without verified support. Damaged or newer-version saved storage is preserved, with recoverable profiles readable and disk saves disabled; valid working-draft edits remain available in memory.

## Automated and manual verification

```sh
xcodebuild test -project 'XM5 Control.xcodeproj' -scheme 'XM5 Control' -destination 'platform=macOS' -derivedDataPath /tmp/xm5-xm6-derived-data
```

The scheme includes unit tests and an interactive UI suite. DEBUG UI scenarios cover XM5, XM6, unavailable EQ, offline editing, rejected writes, model changes, and storage recovery without contacting physical headphones.

See [protocol evidence and verification results](docs/testing/xm6-protocol-evidence.md), [the hardware checklist](docs/testing/xm5-xm6-manual-checklist.md). Record the exact build, macOS version, and headphone firmware for hardware results. Any XM5 regression blocks release.

## Landing page

The React + Vite landing page lives in [`website/`](website/). See its [setup instructions](website/README.md) for local development and Vercel configuration.

## Open source

XM5 Control is open source under the [MIT License](LICENSE). You can use, modify, and distribute it, including in commercial projects, as long as the original copyright and license notice are included.

Contributions are welcome. Please open an issue before starting a large feature or protocol change so the work can be coordinated.
