# Implementation status

Implementation committed through `d278e16ae6b91f2f7684a3a2649aa756924fa578` for M0–M5; independent reviewer/tester acceptance and hardware/account-dependent validation remain pending. Private development branch, no public release, PR or merge.

| Requirement | Implementation | Evidence / remaining validation |
|---|---|---|
| R01 Native Mac | NSApplication/menus, NSDocument, operator NSWindow and native editor, SwiftUI controls | Developer local builds and AppKit window/key-event tests pass; cached NSView bitmap is incomplete for SwiftUI layer controls; full manual accessibility/sandbox walkthrough pending |
| R02 TXT | Shared Open/drop importer, strict Unicode/BOM decoding, explicit recovery preview, bounded reads | Core encodings plus AppKit originals/round-trip tests pass |
| R03 RTF | Explicit native RTF parser, emphasis/color source retention, unsupported diagnostics, derived copy | Real RTF/HTML refusal/diagnostic/source-preservation tests pass; full complex-content fidelity not promised |
| R04 iCloud | Entitled container discovery, normal NSDocument save, metadata/download/identity handling, Versions/copy paths and take isolation | Local/unconfigured metadata and replacement/save-protection tests pass; owner signing, two-Mac delivery/offline conflicts pending |
| R05 Typography | Family/size/mode/colors/spacing/column/guide controls and snapshot-scoped anchors | Source byte identity, bold and anchor tests pass; visual fonts/VoiceOver pending |
| R06 Transport | Pure timeline, live speed slider/field/stepper, play/pause/restart/stop | Core timing and actual session tests pass |
| R07 Smooth scrolling | View-associated display link, common mode, host target timestamps, fractional layer movement, bounded lookahead, stall/sleep policy | Refresh-grid/stall/long-script/link-lifetime tests pass; real 1×/2× mixed-refresh smoothness and sustained profiling pending |
| R08 Reflection | Independent center-based horizontal/vertical transforms; unmirrored preview/calibration option | Core all-four transform tests pass; optical glass validation pending |
| R09 Output | Clean borderless selected-screen window, UUID/name preference, common logical preview, disconnect pause and reliable exit | Actual screen-frame window and simulated-loss tests pass; physical negative origins/Spaces/scaling/minimized operator pending |

M0: runnable app/project/shared scheme/core with fake-clock checks. M1: import/native persistence/editor/derived source-safe styling. M2: display-linked timeline/anchors/lifecycle. M3: independent output/reflection/logical preview. M4: real FileManager/NSDocument iCloud integration with owner configuration. M5: validation, focus safety, fixture generator and docs. No fake cloud success adapter, external dependency, document-content logger or hardware identifier log exists.

Actual executed evidence and the Xcode hosted-launcher assertion are in README. The direct bundle runner executes the compiled hosted test suite; it does not erase the scheme-launch failure or establish sandbox proof. Developer logs report 9 core Swift Testing tests and 11 direct AppKit bundle tests passing. No full application checks were rerun for this metadata-only integration; the independent test worker must validate the combined tip. The cached NSView bitmap is limited visual evidence with incomplete SwiftUI layer controls. Screen-capture permission is unavailable; no complete real-window screenshot or hardware visual pass is claimed.

Remaining limitations in priority order: (1) owner-signed two-Mac conflict/recovery and account/download validation; (2) physical low-speed/output/Spaces/lifecycle and 60-minute profiling; (3) manual accessibility/tab-order and complex RTF review; (4) Xcode LaunchServices hosted test launcher assertion on this environment. No release-readiness claim is made. See the manual plan for pass/fail criteria.

Work tracking: [MVP cueglass-aeqt](../.beans/cueglass-aeqt--cueflow-v1-mvp.md), with all acceptance checklist items open, and [ADR index](adr/README.md). ADR 0001 is delivered; architecture decision acceptance does not accept the MVP. Remaining follow-ups: [owner iCloud / two Macs](../.beans/cueglass-ykl0--owner-icloud-setup-and-two-mac-verification.md), [physical display / visual](../.beans/cueglass-feeg--physical-display-and-visual-verification.md), and [hardware performance](../.beans/cueglass-c1kt--performance-profiling-on-hardware.md).
