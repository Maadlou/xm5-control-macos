# XM5 Control for macOS

A native SwiftUI menu-bar controller for Sony WH-1000XM5 headphones.

## Current features

- Finds a paired WH/WF-1000XM5 through macOS IOBluetooth.
- Opens Sony's `Serial HPC` service over RFCOMM.
- Implements the MDR V2 handshake and framed transport.
- Reads live noise-control state and notifications.
- Controls Off, Noise Cancelling, and Ambient modes.
- Controls ambient level and Focus on Voice when supported.
- Reads the headset battery level and charging state over MDR V2.
- Shows live battery or listening mode in the macOS menu bar.
- Includes Focus, Office, and Aware one-click listening presets.
- Reads and changes Sony equalizer presets, including Bright, Vocal, Bass Boost, and Speech.
- Includes a live custom EQ editor for Clear Bass and five frequency bands, with reusable personal presets.
- Provides a permission-free global `⌥⌘A` shortcut to toggle Noise Cancelling and Ambient mode.
- Supports native launch at login and optional automatic control-link reconnection.
- Uses capped reconnect backoff, distinguishes Bluetooth audio from Sony control-link availability, and periodically resyncs phone-side changes.
- Provides copyable connection diagnostics including firmware, protocol channel, last sync, and last error.
- Uses a transparent user-supplied headphone hero with mode-aware visuals.

## Development

Open `XM5 Control.xcodeproj` in Xcode 26 or newer. The app targets macOS 14 or newer.

The development bundle identifier is `local.xm5control`. Replace it with a globally unique identifier before signing or distribution.

The headphones must be paired and powered on. Only one process can own the Sony RFCOMM channel at a time, so quit other Sony-control utilities while testing.

The active ANC, ambient, preset EQ, and manual EQ curve are device settings and can be read by Sony Sound Connect. Named presets created by XM5 Control are stored locally on the Mac; applying one sends its curve to the headphones, but its custom name is not inserted into Sony's app-private preset library.

## Attribution

The Sony protocol framing and NC/ASM command sequence were adapted from [TheGeekyM/xm5-control](https://github.com/TheGeekyM/xm5-control), licensed under the MIT License. Battery and equalizer command behavior was cross-checked against [AmitRajput-Dev/SonyBridge](https://github.com/AmitRajput-Dev/SonyBridge), also MIT licensed.

The `XM5Hero` artwork is a user-supplied product image with its background isolated for the app. Confirm redistribution rights before publishing binaries or source assets. Sony, WH-1000XM5, and Sound Connect are trademarks of Sony Group Corporation; this project is unofficial and is not affiliated with or endorsed by Sony.
