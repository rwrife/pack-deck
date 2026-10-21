# Accessibility audit — M7 (#7)

## Scope and evidence boundary

Kit library/editor, trip list/builder, packing workspace, and data transfer.
The automated journey requests the largest Dynamic Type category (AX5,
`UICTContentSizeCategoryAccessibilityXXXL`) and checks the resolved SwiftUI
category before testing. It records screenshots and accessibility-tree text
attachments in `UITestResults.xcresult`, then calls Apple's
`performAccessibilityAudit()`. Findings are collected per screen and fail the
test at its final assertion; the handler defers failure only to reach later
screens. Findings with an unresolved element also remain failures.

**Status: native audit failed; fixes remain unverified.** Run
[37784207877](https://github.com/rwrife/pack-deck/actions/runs/37784207877)
built successfully on the exact pin and verified the app's iPhone family and
bundle ID. It executed 11 UI tests: 9 passed, 2 new audit tests failed:

```
Dynamic Type font sizes are partially unsupported
Contrast failed
Executed 11 tests, with 2 failures (0 unexpected)
```

The library audit stopped at the first finding; later primary-screen audits
were not reached. The builder audit failed contrast after focus/Return
assertions passed. Findings are not waived or attributed to runner flake.
Run [37931337063](https://github.com/rwrife/pack-deck/actions/runs/37931337063)
compiled on the pinned Xcode, built the iPhone-only app (`UIDeviceFamily == [1]`,
`com.infinityball.packdeck`), and ran all 11 UI tests: 9 passed, 2 audit tests
failed. The Kit library audit reported `Contrast failed for
SwiftUI.AccessibilityNode` with `element: nil`; the trip builder audit identified
`trip.create` (`Create`, Disabled) with the same contrast finding. The contrast
audit stopped before the remaining screens. These are unresolved findings, not
waived. The diagnostic attachments and full UI logs are retained in that run.
Run [37936642609 attempt 3](https://github.com/rwrife/pack-deck/actions/runs/37936642609) tested the exact PR head (`6d9c8485deeed785d861f0b597c172b0743b5a22`) on pinned Xcode 26.0.1 / 17A400 and SDK 26.0. The iOS simulator build passed; the built app asserted `UIDeviceFamily == [1]` and `com.infinityball.packdeck`. The UI suite ran 11 tests: 9 passed, 2 audit tests failed (exit 65). Unlike attempts 1–2 (simulator launch timeouts with no test cases), this attempt reached all primary screens and retained trees/screenshots and findings in [artifact `uitest-results-3`](https://github.com/rwrife/pack-deck/actions/runs/37936642609/artifacts/11702576885). Findings were not waived:

| Screen | Reported audit findings |
| --- | --- |
| Kit library | Contrast (unresolved SwiftUI node), Dynamic Type on the test probe, text clipping (unresolved node) |
| Kit editor | Contrast (unresolved SwiftUI node), Dynamic Type on `kit.edit`, `kit.cancel`, `kit.item.add`, `kit.save`, and the test probe; text clipping on `kit.item.add` and the long `kit.name` text field |
| Trip list | Contrast (unresolved SwiftUI node), Dynamic Type on the test probe |
| Packing workspace | Contrast (unresolved SwiftUI node), Dynamic Type on the test probe |
| Data transfer | Contrast (unresolved SwiftUI node), Dynamic Type on the test probe, clipped `Import JSON Backup` label |
| Trip builder | Dynamic Type on `Cancel` and disabled `trip.create`, clipped `trip.tags` placeholder, contrast on disabled `trip.create` |
| Status/Undo journey | Dynamic Type on the test probe, contrast on the `Packing list` heading |

The AX5 test probe is a fixed `.caption2` text under the tab bar; its audit finding does not establish a production-text scaling failure. The other findings are real audit reports and require targeted remediation and a fresh native run. An unresolved node is **not** assumed to be a false positive. Automated keyboard Return dismissal and the status/Undo journey passed their assertions, but those assertions do not satisfy manual input and VoiceOver acceptance.
Linux syntax/package checks are not an iOS accessibility result. A green exact-head native audit and manual evidence are still required before this report can be marked verified; do not merge or close #7.
No device, signing, archive, or TestFlight evidence is claimed.

### Remediation run 38271353633 (head `33c576de`)

Run [38271353633](https://github.com/rwrife/pack-deck/actions/runs/38271353633) on pinned Xcode 26.0.1 built the app and ran 11 UI tests: 9 passed, 2 audit tests still failed (`Executed 11 tests, with 2 failures`). Commit `33c576d` made the probe `.body` primary text, shortened the tags placeholder, and removed the icon from `Import JSON Backup`. Compared with run 38140970153, these are gone: the probe Dynamic Type finding, the `tab.data`/`transfer.importJSON` clipping, and the `trip.tags` clipping. Still reported, not waived:

| Finding | Element |
| --- | --- |
| Dynamic Type partially unsupported | `kit.save`, `kit.cancel`, `kit.edit`, `kit.item.add`, `trip.create`, trip builder nav bar |
| Text clipped | `kit.name` field, `kit.item.add` |
| Contrast failed | `trip.create` (disabled) and 5 unresolved SwiftUI nodes |

Next candidates: remove the fixed `.frame(minWidth: 44, minHeight: 44)` on toolbar buttons (it may defeat scaling), find the unresolved contrast nodes from the retained trees, and make `kit.name` multiline without breaking Return-to-dismiss in `KitLibraryUITests`. The status stays failed until a fresh exact-head run passes.

### Exact-head rerun 38279780753 (head `4d331b6`)

[Run 38279780753](https://github.com/rwrife/pack-deck/actions/runs/38279780753) completed with Linux package tests green and the pinned iOS build passing the built-app iPhone-family and bundle-ID checks. The UI lane executed 11 tests: 9 passed, 2 accessibility audits failed. No new app fix was validated. The job log identifies the kit-library note `Charger, travel adapter, and daily medication` as one concrete contrast failure; that text currently uses `.foregroundStyle(.secondary)` in `KitRow`. Other contrast reports have `element: nil` and cannot yet be attributed from the log. Kit editor reports clipped `kit.name` and `kit.item.add`; toolbar controls report partial Dynamic Type support, while the disabled `trip.create` reports both partial support and contrast failure. Do not waive these findings or remove the 44pt hit-target frames without rerunning the issue-#4 hit-target test. Log evidence disproves the earlier theory that the `.frame(minWidth: 44, minHeight: 44)` toolbar treatment causes the Dynamic Type finding: the New Trip `Cancel` button (`TripBuilderView`, no custom frame) and the system `EditButton` (`kit.edit`) are flagged identically, so the finding is generic to iOS 26 SwiftUI toolbar buttons at AX5 and cannot be fixed by deleting frames. Remaining decision for the owner: replace toolbar buttons with in-content controls, or accept/waive the system toolbar finding explicitly in the audit handler. The retained [xcresult artifact](https://github.com/rwrife/pack-deck/actions/runs/38279780753/artifacts/11761048708) needs screenshot/tree review on Apple tooling; no manual VoiceOver, external keyboard, or Reduce Motion walkthrough was performed. Keep draft and issue open.

The identified kit-note contrast failure now uses primary text foreground. [Run 38581151255](https://github.com/rwrife/pack-deck/actions/runs/38581151255) built the iPhone-only app on the pinned Xcode, verified `UIDeviceFamily == [1]` and `com.infinityball.packdeck`, then ran 11 UI tests: 9 passed, 2 accessibility audits failed (exit 65). The earlier kit-note contrast finding did not recur; the audit still reports unresolved contrast and clipping nodes, kit toolbar Dynamic Type findings, a clipped kit-name field/Add Item button, a `Checklist Export` contrast finding, a disabled `trip.create` contrast finding, and `Packing list`/`Set status` contrast findings. The trip/workspace secondary-text foreground changes did not eliminate these remaining findings. No finding has been waived. Keep draft and issue open.

### Exact-head audit 38585648423 (head `ab7f131`)

[Run 38585648423](https://github.com/rwrife/pack-deck/actions/runs/38585648423) passed Linux package tests, built on pinned Xcode 26.0.1 and SDK 26.0, checked the built app's `UIDeviceFamily == [1]` and `com.infinityball.packdeck`, then executed 11 UI tests: 9 passed, 2 accessibility audits failed (`** TEST FAILED **`, exit 65). AX5 journeys reached the library, editor, trip list, workspace, transfer screen, trip builder, and status/Undo checks. The log and retained [xcresult artifact](https://github.com/rwrife/pack-deck/actions/runs/38585648423/artifacts/11906362932) identify:

| Screen | Current finding |
| --- | --- |
| Kit library | Contrast and text clipping; both reported `element: nil` |
| Kit editor | Two contrast reports with unresolved elements; Dynamic Type on `kit.edit`, `kit.item.add`, `kit.cancel`, `kit.save`; clipping on `kit.item.add` and long `kit.name` value (`Long weekend carry...`) |
| Data transfer | Contrast with unresolved element |
| Trip builder | Contrast and Dynamic Type on disabled `trip.create`; Dynamic Type on `Cancel` |
| Status/Undo | Audit recorded contrast (full assertion includes `Packing list`); status-text and keyboard-dismiss assertions themselves passed |

The trip-list and packing-workspace audit calls emitted no standalone finding before navigation continued; the other screens remain red. Do not infer `element: nil` is harmless, waive findings, or call the partial journeys an audit pass. Review xcresult screenshots and trees on Apple tooling to localize unresolved nodes. Replace the one-line kit-name input with a multiline-safe control only after updating Return/focus UI tests; separately fix the 44-point `Add Item` layout without weakening hit-target coverage. Toolbar Dynamic Type warnings affect both app buttons and system `EditButton`/unframed `Cancel`, so removing hit-target frames alone is not a supported fix. Manual VoiceOver, external-keyboard, and Reduce Motion evidence still missing. Keep draft and #7 open.

### Exact-head audit 38747676837 (head `2ce292c`)

[Run 38747676837](https://github.com/rwrife/pack-deck/actions/runs/38747676837) passed Linux package tests, built on the pinned Apple lane, then executed 11 UI tests: 9 passed, 2 AX5 audits failed (`Executed 11 tests, with 2 failures`; `** TEST FAILED **`). The log reports unresolved contrast and clipping nodes; the editor still reports clipping on `kit.name` and `kit.item.add`, plus partial Dynamic Type support on its toolbar buttons. The builder reports partial support on `Cancel` and disabled `trip.create`. Status/Undo and keyboard Return assertions completed before the final audit finding assertion. This is not a green native audit. A subsequent candidate removes the decorative Add Item glyph to give its text more room; it has not passed a native run. The single-line kit name remains because changing to a multiline TextField would break Return-to-dismiss and existing text-field UI queries without an Apple-verified replacement. No findings are waived. Keep draft and #7 open.

### Exact-head audit 38916135828 (head `128ee9b`)

[Run 38916135828](https://github.com/rwrife/pack-deck/actions/runs/38916135828) built on pinned Xcode 26.0.1 and SDK 26.0, checked iPhone-only and bundle ID, and executed 11 UI tests: 9 passed, 2 AX5 audits failed (`Executed 11 tests, with 2 failures`; `** TEST FAILED **`). Removing the decorative plus glyph on the Add Item button was confirmed in the element dump (measured 96.5x44, hit target intact), but it still reported partial Dynamic Type support along with `kit.save`, `kit.cancel`, `kit.edit`, and `trip.create`. The editor still reported clipped `kit.name` (single-line field `Long weekend carry...`), and data transfer reported a contrast finding on the `Checklist Export` section header. No finding is waived. The draft and issue #7 remain open pending a passing native audit and manual accessibility verification.

### Exact-head audit 38927080056 (head `f6fd666`)

[Run 38927080056](https://github.com/rwrife/pack-deck/actions/runs/38927080056) passed Linux package tests (`swift test` on PackDeckKit and PackDeckStore, zero-network and native-only gates), selected the exact pinned toolchain (Xcode 26.0.1 / 17A400 / SDK 26.0), verified iPhone-only settings (`UIDeviceFamily == [1]`), ensured the iOS 26.0 simulator runtime, built for iphonesimulator, and verified built `UIDeviceFamily == [1]` and `com.infinityball.packdeck` bundle identifier. The UI test suite executed 11 tests: 9 passed, 2 accessibility audits failed (`Executed 11 tests, with 2 failures (0 unexpected)`, exit 65).

The failures in `AccessibilityAuditUITests`:
1. `testLargestTextAndReadingOrderAcrossPrimaryScreens` failed with audit findings including:
   - Contrast failure on `Charger, travel adapter, and daily medication` static text in kit row (`KitRow`).
   - Contrast failures on `Kit` and `Items` section header static texts in `KitEditorView`.
   - Contrast failures on unresolved SwiftUI accessibility nodes (`element: nil`).
   - Dynamic Type partially unsupported on `kit.item.add` (`Add Item`), `kit.cancel` (`Cancel`), `kit.edit` (`Edit`), and `kit.save` (`Save`).
   - Text clipped on `kit.name` (`TextField` with long value `Long weekend carry...`).
2. `testStatusTextAndKeyboardFocusContract` failed with 3 audit findings:
   - Dynamic Type partially unsupported on disabled `trip.create` (`Create`) and `Cancel` button in trip builder navigation bar.
   - Contrast failure on disabled `trip.create` button.

All findings remain documented, un-waived, and active blockers for PR #15 readiness. No manual VoiceOver, external keyboard, or Reduce Motion physical walkthrough has been completed. Issue #7 and PR #15 remain open in draft state.

### Exact-head audit 39443439261 (head `6764dab`)

[Run 39443439261](https://github.com/rwrife/pack-deck/actions/runs/39443439261) passed Linux package tests (`swift test` on PackDeckKit and PackDeckStore, zero-network and native-only gates), selected the exact pinned toolchain (Xcode 26.0.1 / 17A400 / SDK 26.0), verified iPhone-only settings (`UIDeviceFamily == [1]`), ensured the iOS 26.0 simulator runtime, built for iphonesimulator, and verified built `UIDeviceFamily == [1]` and `com.infinityball.packdeck` bundle identifier. The UI test suite executed 11 tests: 9 passed, 2 accessibility audits failed (`Executed 11 tests, with 2 failures (0 unexpected)`, exit 65).

Result of section header contrast changes:
- In `KitEditorView`, explicit `.foregroundStyle(.primary)` headers for `Kit` and `Items` eliminated the previous contrast failures for both labels.
- In `TripViews` and `DataTransferView`, `Packing list` and `Checklist Export` header contrast findings did not recur.

Remaining findings reported across tests:
1. `testLargestTextAndReadingOrderAcrossPrimaryScreens`:
   - Contrast on `kit.save` button and unresolved SwiftUI nodes (`element: nil`).
   - Dynamic Type partially unsupported on `kit.cancel`, `kit.edit`, `kit.item.add`, and `kit.save`.
   - Text clipped on `kit.name` (`TextField` with long value `Long weekend carry...`).
2. `testStatusTextAndKeyboardFocusContract`:
   - Dynamic Type partially unsupported on disabled `trip.create` and `Cancel` button.
   - Contrast failure on disabled `trip.create` button.

All remaining findings remain documented, un-waived, and active blockers. Manual VoiceOver, external keyboard, and Reduce Motion physical walkthrough remain unperformed. Issue #7 and PR #15 remain open in draft state.

### Exact-head audit 39451720456 (head `82868bc`)

[Run 39451720456](https://github.com/rwrife/pack-deck/actions/runs/39451720456) passed Linux package tests and pinned iOS build/family/bundle checks. UI tests executed 11 tests with 4 failures (exit 65): both unwaived accessibility audits, plus `testKitEditorSurvivesExtraLargeDynamicType` (after Add Item tap, lazy `kit.item.name` row not found at AX5) and `testCreateTripFromKitPackAndUpdateProgress` (progress did not return to `0 of 1` after Undo within five seconds). New test diagnostics scroll the AX5 Form to reveal the item and report the full accessibility hierarchy/status on an Undo failure. Those changes still need exact-head Apple CI validation. Audit still identifies clipped `kit.name`, unsupported toolbar Dynamic Type, contrast on `kit.item.add` and disabled `trip.create`, contrast on `Packing list` and `Set status`, and unresolved nodes. Section header contrast changes from the prior run did not stay green across this run; no contrast finding is waived. Keep PR draft and #7 open.

## Findings and fixes

| Finding from source inspection | Fix | Evidence required |
| --- | --- | --- |
| Kit name and notes preview explicitly limited to one line | Multiline text; count and notes vertically stacked | AX5 library screenshot + native audit |
| Kit quantity/category controls compete for horizontal space | `AnyLayout` stacks at accessibility text sizes | AX5 editor screenshot + native audit |
| Kit notes field capped at three lines | Remove upper line cap | AX5 editor screenshot |
| Trip ad-hoc field and Add compete for width | Stack at accessibility text sizes | AX5 builder screenshot + native audit |
| Trip fields lack deterministic Return focus release | Focus bindings and `onSubmit` release | Focus journey; keyboard dismissal assertion |
| Nonessential SwiftUI transactions could animate with Reduce Motion | Root transaction clears animation and disables animations when system preference is on | Source inspection; manual preference walkthrough remains |

## Reading and focus order

Default SwiftUI source order is retained; no artificial sort priorities or
container identifiers hide child controls. Library rows combine name/count;
builder order is name, nights, laundry, tags, kits, ad-hoc items; workspace
order is progress, filters, each item name/status/reason, status action, Undo.
The journey retains the actual accessibility trees for review. Apple's audit
checks exposed descriptions and traits; it is not a recording of VoiceOver
speech or proof of every rotor mode. A human VoiceOver walkthrough and physical
external-keyboard Tab/Shift-Tab navigation remain untested. Do not call those
manual checks passed from the focus/Return automation.

## Color and motion

Each packing status is spelled out in text (`Planned`, `Packed`, `Missing`,
`Omitted`) beside recommendation quantity. Progress is numeric text, not a
color-only bar. The new journey changes status to Missing and undoes it,
asserting both text states. No app-owned repeating/custom animation exists;
system navigation respects iOS preferences and the root transaction now
suppresses SwiftUI animations under Reduce Motion. Actual system-setting and
VoiceOver behavior still need device/manual review.

## Reproduction

Run the existing `PackDeck` scheme's `PackDeckUITests` target on the pinned
Apple environment. The CI workflow uploads `ui-tests.log` and
`UITestResults.xcresult`; `AccessibilityAuditUITests` adds the AX5 screenshots
and tree attachments. Normal launches contain neither fixtures nor the probe.
Fixture creation is launch-flag-gated, uses the real store/planner, and does not
replace existing data.

## Acceptance checklist

- [ ] Exact-head native audit and AX5 primary-screen journeys passed (Run 37936642609 recorded 2 failures; findings table documented above).
- [ ] Recorded accessibility-tree/audit findings reviewed for logical order.
- [x] Status semantics are text, not color alone (source; native assertions passed).
- [x] Reduce Motion transaction guard implemented (source; manual check pending).
- [ ] Manual VoiceOver/external keyboard/Reduce Motion walkthrough recorded.

Until the native evidence and remaining manual limitations are reviewed, keep
this work draft and #7 open. A green Linux job alone cannot close it.
