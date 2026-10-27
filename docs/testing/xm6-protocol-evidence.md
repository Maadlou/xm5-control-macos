# XM6 protocol evidence

Inspected 2026-10-27. Scope: implementation tasks 1-7 and the subsequent live connection fix. A WH-1000XM6 firmware 3.1.5 protocol-info reply was captured locally; full ANC/EQ hardware acceptance remains pending.

## Pinned references

- [XM6 command implementation](https://github.com/PrathameshSujgure-git/xm6-control/blob/124c1a16e711c14c3a5b5a2f6974e0fedd5fac68/Sources/XM6Control/XM6Commands.swift), [transport](https://github.com/PrathameshSujgure-git/xm6-control/blob/124c1a16e711c14c3a5b5a2f6974e0fedd5fac68/Sources/SonyProtocol/RFCOMMTransport.swift), and [README](https://github.com/PrathameshSujgure-git/xm6-control/blob/124c1a16e711c14c3a5b5a2f6974e0fedd5fac68/README.md). The maintainer reports WH-1000XM6 firmware 3.0.0 testing; that report is not a local test result.
- [SonyHeadphonesClient common v2 definitions](https://github.com/mos9527/SonyHeadphonesClient/blob/d718306167c3281f2836a88895723ad4a19b87f9/libmdr/include/mdr/ProtocolV2.hpp) and [table-1 definitions](https://github.com/mos9527/SonyHeadphonesClient/blob/d718306167c3281f2836a88895723ad4a19b87f9/libmdr/include/mdr/ProtocolV2T1.hpp). These distinguish capability function IDs from command inquired types and define protocol version, battery charging fields, and ANC layouts.
- Local baseline: commit `b2554b32ec833bbf4dc73f1477f8a52d075ac2a9`, `Sources/SonyProtocol.swift` and `Sources/SonyHeadphonesController.swift`.

## Implemented format decisions

| Feature | Evidence and decision |
|---|---|
| Transport | Existing Serial HPC UUID `956C7B26-D49A-4BA8-B03F-B17D393CB6E2` is the XM6 reference's first UUID. Keep it unchanged. Its second, older UUID and conflicting README reports elsewhere do not justify a new fallback without local SDP evidence. |
| Handshake | Query `00 00`. Table-1 return: `01 00`, big-endian UInt32 protocol version, then table-1/table-2 enable bytes (0 = enabled, 1 = disabled). Validate the eight-byte layout and table flags. The four-byte revision is opaque and must not be compared to the integer family number 2. Require table 1, then validate advertised functions and known response layouts before enabling controls. |
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

The original fixtures were constructed from the pinned definitions above. The protocol-info payload documented in the live investigation below was captured locally and is explicitly identified in its regression tests. Other packets in those tests remain constructed fixtures. XM5 exact byte assertions and literal pre-migration JSON are characterization fixtures for existing application behavior. New tests must distinguish those from reference-derived XM6 fixtures.

- Baseline before changes: 7 unit tests passed, zero failures (Xcode 27.1).
- Characterization: all XM5 factory IDs, six-value EQ encoding/clamping/round-trip, and literal saved draft/profile JSON.
- Hardware acceptance remains pending in [the manual checklist](xm5-xm6-manual-checklist.md). Verify actual capability list, handshake, ANC variants, charging, EQ subtype/presets/gains on the user's firmware. Reference-source agreement is not a device test.

## Tasks 1-4 implementation verification

- Final unit suite: 32 tests, zero failures. Includes independent literal ANC eight/nine-byte responses, XM6 -6/+6 wire endpoints, strict malformed-packet rejection, legacy backup preservation, layout isolation, and read-only recovery with successive in-memory edits.
- Release build: succeeded with the existing app target and bundle identity.
- Existing UI suite: 6 tests, 4 failures. The original `b2554b3` revision reproduced the same four failing tests at the same assertion locations: custom EQ menu lookup, mode-detail accessibility, settings keyboard navigation, and settings surface accessibility. These checks remain unverified; they are not reported as passing or repaired by Tasks 1-4.
- Independent code review identified a read-only draft defect. A regression test failed before the fix and passed afterward. Disk writes remain blocked when the original storage is damaged; valid in-memory edits still update the editor's working draft.
- Live XM6 discovery, negotiated session integration, and dynamic ten-band UI remain Tasks 5-6. The running app is still XM5-only at this checkpoint.

Logs and result bundles from this implementation run:

| Check | Evidence |
|---|---|
| Baseline units | `/tmp/xm5-xm6-baseline.log` |
| Final units | `/tmp/xm5-xm6-final-unit.log`; `/tmp/xm5-xm6-derived-data/Logs/Test/` |
| Current UI | `/tmp/xm5-xm6-ui-regression.log`; `/tmp/xm5-xm6-derived-data/Logs/Test/` |
| Original-revision UI | `/tmp/xm5-xm6-ui-baseline.log`; `/tmp/xm5-xm6-ui-baseline-derived-data/Logs/Test/` |
| Release | `/tmp/xm5-xm6-release-build.log` |

Temporary logs may expire. No local headphone result is implied by these automated checks.

## Tasks 5-7 implementation verification

Live discovery now uses the connected-first, stable-device policy. Each control session owns a UUID, stream, sequence, timers, negotiated capabilities, and confirmed state. Replacing a session cancels delayed writes/readbacks/retries and ignores callbacks from other channels. Opening and handshake phases time out after 8 seconds. Interactive writes retain the final debounced request, query after 250 ms, and fail after 3 seconds without matching readback. Notifications update confirmed state, but do not alone complete a pending write.

Noise control remains available when EQ is unadvertised, has an unsupported layout, or never responds to the initial query. The editor and both profile pickers use the negotiated layout. Offline editing uses an explicitly labelled layout, and switching simulated generations while the editor is open is covered by UI tests. DEBUG fixtures never open the physical control link; hosted unit tests use isolated preferences.

- Pre-review combined suite: 42 unit tests and 13 UI tests, zero failures in `/tmp/xm5-xm6-final-tests.log`.
- The previous UI query failures were corrected using observed macOS accessibility roles and stable identifiers. The original six XM5 UI checks now pass alongside the new scenarios.
- Both profile pickers exclude incompatible curves. The XM6 last band is reachable by scrolling and adjusts to +6 through XCTest's native slider action.
- Simulated XM6 editor visually inspected from a test recording: all ten labels/sliders fit correctly, with saved profiles below in the scroll view. DEBUG model-switch buttons are excluded from ordinary app use and Release builds.
- Landing page: locked existing dependencies installed with pnpm 10.34.3; Vite production build passed (`/tmp/xm5-xm6-website-build.log`). No dependency or lockfile changes were made.
- Release configuration verification is recorded in `/tmp/xm5-xm6-final-release.log`.

These are automated/simulated results. WH-1000XM5 regression acceptance, WH-1000XM6 device/firmware verification, and mixed-device hardware acceptance remain Pending in the manual checklist. No release is marked hardware-verified by this change.

### Final review fixes and verified checkpoint

The independent review found three state-interleaving defects. Each was reproduced before its fix:

1. A delayed A readback could confirm a replacement A request after an intervening B write. There is now one outstanding query per feature, including initial/manual/poll queries. A query retains its operation owner across edits. An old reply drains that query before the replacement's query is issued, and cannot complete the replacement operation. An unanswered query is never reassigned; explicit Sync starts a fresh session when needed.
2. A rejected Custom write could replace the working draft with the device's previous curve. The editor tracks locally edited layouts and retains dirty values across failed writes and unrelated noise edits. Successful matching confirmation or explicit EQ Sync can adopt device values.
3. A preset-only Custom response could make an initialized or stale curve appear confirmed. The controller now tracks whether actual band values were reported for the current state. Preset-only responses update the preset label but cannot overwrite a draft or display Synced.

Final results after these fixes:

- 46 unit tests and 15 UI tests passed, zero failures: `/tmp/xm5-xm6-final-verified-tests.log`.
- Release build passed: `/tmp/xm5-xm6-reviewed-release.log`.
- Release bundle signature verification passed. App name remains `XM5 Control`, bundle identifier remains `local.xm5control`, and minimum macOS remains 14.0.
- Website production build passed; its dependency manifests and lockfile are unchanged.
- The regression cases include delayed A/B/A EQ and noise responses, manual/poll query ownership, missing-reply resynchronization, Custom without band values, dirty-draft preservation after an unrelated noise edit, and deliberate Sync adoption.

Hardware acceptance remains pending. The original RFCOMM framing/ACK transport was retained; Bluetooth delivery, firmware-specific behavior, SDP publication, sleep/reconnect behavior, and multipoint interaction still require the user-run checklist. No publishing or release distribution was performed.

## Live WH-1000XM6 connection investigation

Device: WH-1000XM6, firmware 3.1.5, observed locally on 2026-10-27. Bluetooth audio was connected and the Sony control channel opened, but the app rejected the protocol reply before requesting supported functions.

Captured protocol-info payload:

```text
01 00 03 00 30 32 00 00
```

The codec correctly decoded revision `0x03003032` (decimal 50343986) and enabled command tables. The controller incorrectly required the revision to equal literal `2`, confusing the protocol family with the revision field. The [pinned reference initialization and handler](https://github.com/mos9527/SonyHeadphonesClient/blob/d718306167c3281f2836a88895723ad4a19b87f9/libmdr/src/HeadphonesV2.cpp) stores the revision and gates initialization on table-1 support instead.

The fix retains the revision for diagnostics, requires table 1, and continues validating functions and known payload layouts. Missing/malformed handshakes and disabled table 1 still fail. XM6 DEBUG scenarios now use the captured reply rather than an invented literal version 2.

Verification:

- The captured controller regression failed before the fix and passed afterward.
- 48 unit tests and 15 UI tests passed: `/tmp/xm5-xm6-live-handshake-green.log`.
- Corrected Release build passed: `/tmp/xm5-xm6-handshake-fixed-build.log`.
- The independently identified corrected Release process logged the captured revision and then `Sony controls ready; model=whXM6, mode=ambient`: `/tmp/xm5-xm6-fixed-live.log`.
- This confirms real-device handshake completion and noise-state readback. No ANC/EQ setter was used to verify this connection fix. Audio continuity, battery/charging accuracy, EQ reads/writes, and the rest of the manual checklist are not implied to pass.

A narrow independent code review found no Critical or Important issues in this fix.
