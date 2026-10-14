# Implementation status

Owner-expanded R01–R16 and Quiet Studio implementation are delivered for developer verification. MVP `cueglass-aeqt` stays in-progress with every independent acceptance item open. No PR, merge or release is created by this implementation round. Original owner specs were merged from main without rewriting them.

| Requirement | Implementation | Developer evidence / remaining boundary |
|---|---|---|
| R01 native Mac | NSDocument, native menus/windows/editor, unified toolbar, responsive split view and grouped inspector | Native launch/cached renders and geometry checks; actual key-window/menu, accessibility and macOS 14 runtime manual |
| R02 TXT | Shared Open/drop, strict Unicode/BOM/explicit encoding choice and size validation | Core/native/probe outcomes; full panel/drop UI walkthrough manual |
| R03 RTF | Explicit native parser, preserved authored emphasis/colors, diagnostics and derived copy | Real RTF/HTML/size/source-preservation tests; complex document fidelity manual |
| R04 iCloud | Real container/download/resource APIs and NSDocument lifecycle, effective owner plist configs | Settings/unsigned processed plist verified; signed owner/two-Mac behavior pending |
| R05 typography | Curated/other fonts, Medium/Serif API defaults, size/spacing and source-safe modes | Real TextKit line pitch and anchor tests; initial missing-font notice fixed |
| R06 transport | Pure positive-speed timeline, live LPM controls/steps and play/pause | Core/session tests; no frame-count motion |
| R07 smooth motion | View-associated links, host target timestamps, fractional scrolling, bounded lookahead/measurement | Timing/long text/lifecycle tests; actual physical smoothness and sustained profiling pending |
| R08 reflections | Independent center-based axes, logical preview and calibration | Core/actual layer checks; optical glass pending |
| R09 fullscreen output | Selected clean screen-filling window and shared logical layout | Frame/loss tests; real topology/Spaces/scale pending |
| R10 floating | Always-on-top draggable/resizable panel, relative frame persistence/clamp, opacity/click-through, one surface | Native panel/opacity/state/geometry; actual fullscreen-app behavior and hit testing pending |
| R11 Controls | Small HUD with all transport/fine/jump/timers and Show Operator; safe-screen placement | Hidden-operator native key routing; physical display placement/recovery pending |
| R12 pace | LPM source of truth, configured maximum, nominal base advance and estimated WPM | 18–180 pt / line height 1–2 actual fragment-pitch tests; pathological limitation explicitly labelled |
| R13 navigation | Restart, nonblank paragraph steps, separate reverse, pause-and-scrub/momentum gate | Deterministic session/core checks; real trackpad/clicker sensitivity manual |
| R14 commands | Default aliases, remapping/conflicts/reserved validation, local versioned persistence, native responder routing | Core guards/roundtrip and native editor/panel tests; physical peripherals/manual focus routes pending |
| R15 timing | Direction-aware remaining, playing-only elapsed, cancellable mirrored countdown, timed solve/re-solve and bound hold | Deterministic 300-second finish/reverse/restart/cancel; actual countdown visuals manual |
| R16 aids | Guide line/triangles/opacity, gradient fade, side margins, text-panel alpha and hide/restore chrome | Static-aid versus margin relayout tests; contrast and accessibility/real backdrops manual |

## Findings resolved in source and outcome tests

T1: every rejected native read installs overwrite protection, including malformed bytes; recovery to another path remains possible. T2/r1: per-configuration target settings now override XcodeGen's inferred local Info.plist for both cloud configurations; processed unsigned test bundles contain the synthetic literal container key and matching identifier. T3/r1: replacement is fully prepared before mutating a paused take. T4: missing saved font notices appear on open/render/load, not only interactive changes. Native editor Undo/Redo notifications also keep document source coherent.

The independent supplemental probe originally reported 39 assertions with 5 failures; its adapted LPM-era rerun reports zero failures. Aspect-fit native bounds require a 1e-9 pt numerical tolerance; raw exact-double checks differ by about 4e-13 pt, with unchanged session logical dimensions. Raw and adapted evidence are reported separately. New core/native state tests are committed. The DebugLocal scheme uses the unhosted app-linked debug-dylib runner; the current 47-test suite passes. No native test was removed. The original hosted LaunchServices path is historical failing evidence, not a passing hosted launcher. Direct execution remains an optional cross-check, and neither proves signed sandbox behavior.

Developer current suite: 14 core tests, 47 AppKit tests. Paused 100,000-word measurement is chunked across 157 main-loop turns; observed total ~0.35–0.59 s, worst chunks ~3–6.3 ms. This is not steady-state callback proof. Cached actual-launch light/dark renders at 980/1002/1280 show responsive geometry, with activation/key attempts and direct per-view cache checks; cache limitations preclude full window/appearance/menu acceptance. No physical/signed/two-Mac result is invented.

Architecture contracts and schema supersession are in [ADRs 0004/0005](adr/README.md). [Design research/concept](design/README.md) persists official-source rationale and explicitly labels proposed art. See [README](../README.md) for commands and [manual plan](MANUAL_TEST_PLAN.md) for remaining tests.

[Owner cloud follow-up](../.beans/cueglass-ykl0--owner-icloud-setup-and-two-mac-verification.md), [physical/visual follow-up](../.beans/cueglass-feeg--physical-display-and-visual-verification.md), [performance follow-up](../.beans/cueglass-c1kt--performance-profiling-on-hardware.md) remain open. No current-tip independent pass is claimed.

## Quiet Studio correction

Fix5 adds fullscreen/preview matte synchronization for both render and aid-only background changes. The current normal DebugLocal scheme passes 47 native tests, including the actual-controller matte regression; all 14 core tests pass. Removing only the fullscreen backing assignment makes that regression fail with 12 assertions. Floating transparency, whole-window alpha and separate text-panel alpha are retained. Release resources still contain the compiled Reading Line icon.

Focus and accessibility acceptance remain blocked: actual DebugLocal and ReleaseLocal LaunchServices launches stayed inactive under a console session reporting `CGSSessionScreenIsLocked = 1`, with `loginwindow` active and activation returning false. External AX is trusted but window entries report application roles, so neither these results nor cached text resolve the earlier three SwiftUI AX assertions. Repeat the separate-process tree and focus/menu walkthrough in an unlocked session without changing privacy settings. No product focus/AX change is justified by the current evidence.

Balanced native pane widths are 420/578/280 at 1280, with 320/420/260 at 1002 and inspector collapse at 980. The preview fits the unchanged logical output ratio inside a neutral stage. Local dark controls, labelled clocks/progress, state pill, visible Present menu, tracking separators and compact inspector preserve every setting. Paragraph gutter/tint/leading accent are view decoration only; locked editing has Stop Take. New authored text uses 15/22; derived presentation removes fixed source line-height caps so larger reading fonts do not overlap. HUD/grip retain the shared session, opacity, safe-screen and recovery contracts. Independent polish task remains open.
