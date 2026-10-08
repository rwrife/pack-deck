# Accessibility audit — M7 (#7)

## Scope and evidence boundary

Kit library/editor, trip list/builder, packing workspace, and data transfer.
The automated journey requests the largest Dynamic Type category (AX5,
`UICTContentSizeCategoryAccessibilityXXXL`) and checks the resolved SwiftUI
category before testing. It records screenshots and accessibility-tree text
attachments in `UITestResults.xcresult`, then calls Apple's
`performAccessibilityAudit()` without suppressing findings.

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
The follow-up records each audit issue's detailed description and element
into xcresult attachments and logs, so repair can target the actual control.
Linux syntax/package checks are not an iOS accessibility result. The exact-head
macOS CI run must pass before this report can be marked verified. Xcode must remain 26.0.1 / 17A400 with iOS SDK 26.0.
No device, signing, archive, or TestFlight evidence is claimed.

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

- [ ] Exact-head native audit and AX5 primary-screen journeys passed.
- [ ] Recorded accessibility-tree/audit findings reviewed for logical order.
- [x] Status semantics are text, not color alone (source; native assertions pending).
- [x] Reduce Motion transaction guard implemented (source; manual check pending).
- [ ] Manual VoiceOver/external keyboard/Reduce Motion walkthrough recorded.

Until the native evidence and remaining manual limitations are reviewed, keep
this work draft and #7 open. A green Linux job alone cannot close it.
