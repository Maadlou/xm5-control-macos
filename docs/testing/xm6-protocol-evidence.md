# XM6 protocol evidence

Inspected 2026-10-27. Scope: implementation tasks 1–4. No local hardware capture or XM6 compatibility verification has occurred.

## Pinned references

- [XM6 command implementation](https://github.com/PrathameshSujgure-git/xm6-control/blob/124c1a16e711c14c3a5b5a2f6974e0fedd5fac68/Sources/XM6Control/XM6Commands.swift), [transport](https://github.com/PrathameshSujgure-git/xm6-control/blob/124c1a16e711c14c3a5b5a2f6974e0fedd5fac68/Sources/SonyProtocol/RFCOMMTransport.swift), and [README](https://github.com/PrathameshSujgure-git/xm6-control/blob/124c1a16e711c14c3a5b5a2f6974e0fedd5fac68/README.md). The maintainer reports WH-1000XM6 firmware 3.0.0 testing; that report is not a local test result.
- [SonyHeadphonesClient common v2 definitions](https://github.com/mos9527/SonyHeadphonesClient/blob/d718306167c3281f2836a88895723ad4a19b87f9/libmdr/include/mdr/ProtocolV2.hpp) and [table-1 definitions](https://github.com/mos9527/SonyHeadphonesClient/blob/d718306167c3281f2836a88895723ad4a19b87f9/libmdr/include/mdr/ProtocolV2T1.hpp). These distinguish capability function IDs from command inquired types and define protocol version, battery charging fields, and ANC layouts.
- Local baseline: commit `b2554b32ec833bbf4dc73f1477f8a52d075ac2a9`, `Sources/SonyProtocol.swift` and `Sources/SonyHeadphonesController.swift`.

## Implemented format decisions

| Feature | Evidence and decision |
|---|---|
| Transport | Existing Serial HPC UUID `956C7B26-D49A-4BA8-B03F-B17D393CB6E2` is the XM6 reference's first UUID. Keep it unchanged. Its second, older UUID and conflicting README reports elsewhere do not justify a new fallback without local SDP evidence. |
| Handshake | Query `00 00`. Table-1 return: `01 00`, big-endian UInt32 protocol version, then table-1/table-2 enable bytes (0 = enabled, 1 = disabled). Validate eight-byte layout; expose version and table flags without assuming an unknown version is supported. Session integration/timeout remains Task 5. |
| Functions | Query `06 00`; return `07 00 count`, followed by `count` pairs of function ID and priority. Reject truncated lists. Retain IDs; priority is not a capability ID. |
| ANC | Preserve existing preference order `(6D,19), (6B,17), (68,15), (67,22), (66,21)` for function/type. Note `66` advertises ambient on/off and `67` ambient levels: only the latter justifies level/voice controls. Other advertised function families are not implicitly supported. |
| ANC type 19 | Nine-byte response: command, type, change-status, total-effect, NC/ambient mode, voice, level, adaptive-enabled, sensitivity. The XM6 reference also handles eight-byte responses omitting change-status. Decode explicit offsets for each and preserve both adaptive bytes in writes. Other existing variants keep their current write layout. |
| Battery | Function `20` advertises single battery. Query `22 00`; responses `23/25 00 level charging`, level 0...100 and charging 0/1. Three-byte reports cannot establish charging state; reject rather than inventing it. Split-earbud battery is outside this format. |
| EQ | Known supported function families `50` (preset EQ) and `57` (preset EQ with error-code status). Query `56 00`; write `58 00 preset count values`. XM6 reference uses ten values, -6...6 gain, +6 wire offset, no separate Clear Bass. Frequencies: 31, 63, 125, 250, 500 Hz; 1, 2, 4, 8, 16 kHz. |
| EQ incoming | `57 00`, `59 00`, and XM6 `59 04` carry preset, count, values in the reference implementation. Accept only the explicit ten-band XM6 or six-value XM5 layout, exact counts, and valid gains. Zero count means preset-only state. Do not assume `57 04` or other command/subtype pairs share this layout. |
| Presets | XM5 IDs remain `00`, `10...17`, `A0`. XM6 catalogue: Off `00`, Heavy `30`, Clear `31`, Hard `32`, Soft `33`, Custom `A0`. Do not expose `A1...A5` user slots without negotiated/verified support. Unknown IDs remain readable but are not writable catalogue entries. |
| Firmware | Keep request `04 02` and UTF-8 response `05 02 ...`; trim trailing control/space bytes. Reject empty/invalid UTF-8. |

XM5 optional battery/EQ defaults are intentionally retained when metadata is absent, to preserve the current client. XM6 requires known advertised families before enabling these features. Neither an arbitrary unknown function nor a model name alone proves command support.

## Fixtures and verification

All added packet fixtures are constructed from the pinned definitions above, not captured locally. XM5 exact byte assertions and literal pre-migration JSON are characterization fixtures for existing application behavior. New tests must distinguish those from reference-derived XM6 fixtures.

- Baseline before changes: 7 unit tests passed, zero failures (Xcode 27.1).
- Characterization: all XM5 factory IDs, six-value EQ encoding/clamping/round-trip, and literal saved draft/profile JSON.
- Hardware acceptance remains pending in [the manual checklist](xm5-xm6-manual-checklist.md). Verify actual capability list, handshake, ANC variants, charging, EQ subtype/presets/gains on the user's firmware. Reference-source agreement is not a device test.
