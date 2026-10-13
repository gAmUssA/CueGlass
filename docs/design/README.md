# Quiet Studio — native design research and implementation

[Concept board](quiet-studio-concept.svg) is a **proposed design, not a screenshot or user-tested interface**. It persists the owner-requested design consultation, with the later opacity qualification corrected. Final geometry and behavior take precedence over illustrative captions: a 420×124 Controls panel includes all fine/jump controls, actual whole-window alpha ranges 30–100%, and text-panel alpha is separate. The visible app is CueGlass; `.cueflow` remains the document contract.

## Source-backed choices

- [Apple HIG: Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) supports deliberate grouping, recognizable system symbols, avoiding overcrowding and recoverable distraction-free controls. The implementation uses a native unified NSToolbar with transport, Present and inspector groups. Every icon action also has a menu route and accessibility label. Storage stays in File and the title subtitle instead of a wall of buttons.
- [Apple HIG: Typography](https://developer.apple.com/design/human-interface-guidelines/typography) informs semantic operator type, legible weights and system-font APIs. The presentation defaults to System 64 Medium; Serif uses the public design descriptor, not a bundled font. Imported authored fonts/emphasis remain intact, and Preserve Source disables misleading family/weight controls. New typing uses System 15. No font files are bundled.
- [Apple HIG: Panels](https://developer.apple.com/design/human-interface-guidelines/panels) informs a small noun-titled Controls HUD with no minimize button, direct adjustments and a recoverable operator-window action. Native NSPanel preserves the macOS 14 baseline; UtilityWindow would require a later OS.
- [Apple HIG: Layout](https://developer.apple.com/design/human-interface-guidelines/layout) informs content hierarchy, spacing and responsive disclosure. The editor, exact-layout stage and grouped inspector occupy the content area. At 980 pt the inspector collapses; reopening grows toward 1002 pt within the visible screen. Default width is 1280 pt.
- [Apple HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials) and [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) inform native visual effects and semantic colors. Reduce Transparency gets opaque panel backing, Reduce Motion skips fades, Increase Contrast strengthens the guide. State includes text labels; meaning does not depend solely on color.
- [Apple Fonts](https://developer.apple.com/fonts/) informs the decision to use installed system fonts through APIs without redistributing downloaded font files. No commercial embedded face is required.

Sources were read in the accepted design consultation and qualified by the final UX/lead decision. During implementation the official toolbar/typography JSON documentation was accessible; the HTML pages required JavaScript and the panels JSON request was unavailable through the browser tool. SDK compilation with a macOS 14 target verifies the selected API surface, not runtime behavior on a macOS 14 machine.

## Adopted hierarchy and behavior

The old fixed-height, equal-weight control rows are replaced by a document-oriented toolbar and a three-pane split view. The dark stage keeps the output's logical dimensions and scales them. A top take bar carries state, elapsed, remaining, progress and LPM/estimated WPM. The footer carries pace and inline notices. Secondary layout, color, timing and remapping settings use disclosure groups. Font choices are curated, with Other Fonts for the native font panel.

The Controls panel shares the one session and stays available with the operator hidden. It is placed on a safe screen, or hidden when fullscreen output leaves no safe screen; menu/keyboard recovery remains. Floating mode is the single-display path. A floating panel remembers a per-display relative frame and clamps restoration. Real whole-window alpha and the separate text-panel alpha have a worst-case composited contrast warning over black, grey and white backdrops. No opacity is silently changed to hide low contrast.

LPM is authoritative, with positive speed and separate direction. Typography preserves nominal LPM and the guide anchor. A layout-limited effective pace is labelled rather than silently saved. Native key routing is app-local and editor/inspector safe; no event monitor is installed. A start countdown is inside the reflection while timing/progress stay operator-only.

## Evidence and limits

Native integration tests exercise widths 980, 1002 and 1280 pt, editor/stage minimums, inspector collapse, panel commands with hidden operator, whole-window opacity/contrast, LPM from actual TextKit line pitch, reading-aid relayout counts, countdown, source preservation and recovery behavior. Cached NSView images are limited evidence and can omit SwiftUI layer content. They are not WindowServer screenshots. Screen-capture permission is not requested by the app.

Physical slow scrolling, click-through over a fullscreen calling app, optical reflection, actual screen topology, macOS 14 runtime, VoiceOver and system accessibility variants remain manual gates. Proposed concept art and actual test/launch evidence must never be conflated. See [manual plan](../MANUAL_TEST_PLAN.md), [implementation status](../IMPLEMENTATION_STATUS.md), and Beans `cueglass-o9d1` for delivery and `cueglass-7bw1` for independent visual acceptance.
