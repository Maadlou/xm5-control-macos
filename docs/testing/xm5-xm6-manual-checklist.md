# XM5 / XM6 manual hardware checklist

Run after implementation. No hardware checks have been performed as part of writing this document. Use WH-1000XM5 and WH-1000XM6 separately; do not infer one model's result from the other.

Mark each result PASS, FAIL, BLOCKED, or N/A with a reason. A BLOCKED test is not a pass. Keep separate copies/results for each firmware/build combination.

## Build to test

Tasks 5-7 now have automated coverage, including separate XM5/XM6 UI scenarios. Hardware results below are still Pending. Use a fresh build of this branch; the published v0.1.0 download does not contain these changes.

Record `git rev-parse HEAD`, then build:

```sh
xcodebuild build -project 'XM5 Control.xcodeproj' -scheme 'XM5 Control' -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/xm5-xm6-derived-data
```

Quit the current app before launching `/tmp/xm5-xm6-derived-data/Build/Products/Release/XM5 Control.app`. Capture the existing XM5 baseline and preference backup below before installing or launching the new app over your current setup. The bundle identifier remains `local.xm5control` so this is a real upgrade of that preference domain.

The editor shows Applying while a change is pending, Synced after matching custom-EQ readback, Draft when local values differ, Not confirmed after a write failure, and Offline editing without a control link. A successful transport ACK alone does not count as acceptance.

## Test record and preparation

- [ ] Record app commit/build, macOS version, headphone model, firmware, and test date.
- [ ] Record whether upgrading the existing installation or testing fresh preferences.
- [ ] Record whether a phone/second computer is connected through multipoint.
- [ ] Pair the headphones in macOS Bluetooth settings, power them on, and verify audio plays.
- [ ] Quit other Sony-control tools. Start with Sound Connect closed; open it later for the cross-checks below.
- [ ] Photograph/note initial ANC mode, ambient level, voice-focus value, factory/custom EQ values, and app preferences so they can be restored.
- [ ] On the current unmodified XM5 app, save a distinctive named EQ profile and draft; note their exact names/values, shortcut setting, reconnect setting, and launch-at-login setting. Capture baseline behavior for the rows below before upgrading.
- [ ] Back up the existing app preferences using `defaults export local.xm5control /tmp/xm5-control-before-xm6.plist` with the app quit. If using a differently signed bundle, use its actual identifier. Keep the backup until upgrade verification is complete; do not reset preferences for the upgrade run.

## Feature run — complete each column independently

| ID | Action and expected result | XM5 result | XM6 result |
|---|---|---|---|
| H01 | Launch with this model connected. Correct device name/address appears and controls become ready within the configured handshake timeout; audio continues. | Pending | Pending |
| H02 | Read battery and charging state; compare with Sound Connect allowing for display rounding/delay. Firmware and control channel appear in diagnostics. If practical, connect/disconnect charging power and verify the indicator changes. | Pending | Pending |
| H03 | Select Off, ANC, then Ambient. For each, verify the audible effect and confirm the selected state after Sync Now and reopening the panel. | Pending | Pending |
| H04 | In Ambient, set levels 1, 8, and 20. Values read back correctly, persist after Sync Now, and change ambient passthrough. Rapidly drag to a final level; the last value wins. | Pending | Pending |
| H05 | In Ambient, turn Focus on Voice on/off. Confirm through readback and Sound Connect. Switching away from Ambient and back does not corrupt its level or voice setting. | Pending | Pending |
| H06 | Apply Focus, Office, Aware: ANC; Ambient 8 with voice focus; Ambient 20 without voice focus. Confirm actual state, then press ⌥⌘A twice and verify ANC/Ambient toggling. | Pending | Pending |
| H07 | Select each offered factory EQ preset and Off. Confirm active preset through Sync Now and Sound Connect; unsupported/unknown entries are not mislabelled as an XM5 preset. | Pending | Pending |
| H08 | Open Custom EQ. XM5: Clear Bass + 400 Hz/1 kHz/2.5 kHz/6.3 kHz/16 kHz, six sliders, -10...10. XM6: ten frequency sliders, no fabricated Clear Bass, expected -6...6 after evidence validation. No clipped/unreachable controls. | Pending | Pending |
| H09 | Use modest values, e.g. alternating +2/-2, and change every band individually. Sync/reopen and compare all values in Sound Connect. On XM5 also change Clear Bass independently. No shifted/truncated bands. | Pending | Pending |
| H10 | Rapidly drag an EQ slider then release. Only the final intended curve remains after readback; no stuck spinner or false success. Test range endpoints briefly at low volume, then restore. | Pending | Pending |
| H11 | Reset Flat; all controls and the device curve return to zero. Switch to a factory preset, then apply a saved Mac profile or edit a band to activate Custom again. Verify the curve actually applied through Sync Now; opening the editor alone need not activate Custom. | Pending | Pending |
| H12 | Save a named Mac profile, change the curve, apply the saved profile, then quit/relaunch and reapply. Name and every value persist. Delete only the temporary profile afterward. | Pending | Pending |
| H13 | Close the app's control link if necessary to let Sound Connect connect; change mode, ambient level, voice focus, and EQ from the phone. Resume/reconnect the Mac app and Sync Now. It reflects the phone state without overwriting it. Repeat with simultaneous links only if supported. | Pending | Pending |
| H14 | Power off while connected. UI leaves ready state and disables device writes. Power on with automatic reconnect enabled: correct state returns without restarting the app. | Pending | Pending |
| H15 | Turn automatic reconnect off, disconnect/power-cycle, and verify no automatic control-link attempt is made; Connect/Sync explicitly reconnects. Restore preference. | Pending | Pending |
| H16 | Sleep/wake the Mac and disconnect/reconnect through Bluetooth. Correct device and current settings return; there is no stale prior-device battery or EQ. | Pending | Pending |
| H17 | Disconnect during a pending EQ/ambient edit. Pending state resolves to an error/unavailable state within the command timeout. Reconnect: actual device state is shown, and the old write is not unexpectedly replayed. | Pending | Pending |
| H18 | If another controller can occupy the link, reproduce contention. App gives bounded failure/retry feedback and recovers after that tool exits; ordinary audio remains usable. If not reproducible, record BLOCKED. | Pending | Pending |
| H19 | Disable/enable global shortcut, change reconnect preference, and relaunch. Values persist. If login testing is practical, enable launch at login, log out/in, and confirm launch; restore the original setting. | Pending | Pending |
| H20 | Copy Diagnostics. Confirm selected model, firmware, negotiated protocol/capabilities, sync/error details match this run. Capture the report on any failure; redact Bluetooth addresses before sharing publicly. | Pending | Pending |

## XM5 upgrade and mixed-device regression

- [ ] Upgrade without clearing preferences. Legacy profile IDs/names/curves and draft survive exactly; shortcut, reconnect, and launch-at-login settings match the baseline.
- [ ] Quit/relaunch twice. Migration does not duplicate profiles or reset preferences.
- [ ] Apply the legacy XM5 profile to XM5; confirm every value through readback and Sound Connect.
- [ ] Connect XM6: the XM5 profile is not offered as applicable and cannot be sent through either EQ picker.
- [ ] Save an XM6 profile with the same name as an XM5 profile. Switch back: both profiles retain their separate curves and identities.
- [ ] Switch generations while an editor is open. Correct band count/range/draft appears; no indexing crash or write to the wrong device.
- [ ] With disconnected editing, verify the chosen/last-known layout is labelled and editing/saving sends no device commands. Reconnect the other generation: its draft is separate.
- [ ] If an XM5 works with the old app using a prefix-free name containing `1000XM5`, verify that it is still discovered after upgrading. If unavailable, record the matching automated test instead.
- [ ] Pair both generations; connect only XM6. App chooses XM6 despite a paired disconnected XM5. Repeat with only XM5 connected.
- [ ] With both connected, the active device remains stable during polling. Disconnect the active one: the deterministic selection policy chooses the other connected model and clears prior session state.
- [ ] While a write is pending, switch the connected generation. No delayed write/notification from the old session changes the new device or its UI.
- [ ] Re-run the full XM5 feature column after mixed-device testing. Compare against the pre-change baseline.

## Faults that may need a developer fixture

These cannot reliably be induced by ordinary hardware use. Record automated test evidence instead of guessing a manual pass:

- [ ] Unknown EQ preset/subtype/layout: ANC and battery still function; no incorrect EQ write is enabled.
- [ ] Unsupported capability, malformed/truncated packet, or missing handshake response: bounded error/unavailable state, no crash or endless syncing.
- [ ] Acknowledged but unapplied write: readback mismatch is reported and confirmed state remains accurate.
- [ ] Damaged saved profile/migration data: healthy records survive and legacy data is not overwritten.

## Restore and sign off

- [ ] Restore original headphone mode, ambient/voice settings, EQ, and app preferences; remove temporary profiles.
- [ ] Record failures as: test ID, model/firmware, build/macOS, steps, expected/actual behavior, diagnostics, and whether multipoint was active.
- [ ] All required XM5 tests pass with no baseline regression. Any failure blocks release.
- [ ] All required XM6 tests pass before marking WH-1000XM6 verified. List firmware tested and any blocked checks explicitly.

| Sign-off | Result / date / notes |
|---|---|
| XM5 baseline captured | Pending |
| XM5 upgrade and full regression | Pending |
| XM6 full feature run | Pending |
| Mixed-device run (requires both models) | Pending |
| Automated fault coverage | Pending |
| Release decision and remaining limitations | Pending |
