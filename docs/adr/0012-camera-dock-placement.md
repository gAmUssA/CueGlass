# ADR 0012: Camera Dock placement below the camera safe area

- Status: accepted
- Date: 2026-10-16

## Context

Presenters asked for an optional compact prompt near the Mac camera to support near-lens reading. macOS exposes safe-area insets and auxiliary top areas, but it has no app-renderable camera housing or Dynamic Island. The camera housing must stay clear. Existing output surfaces share one immutable take, guide anchor, and playback timeline; a second independent playback surface would violate that contract.

## Decision

Add Camera Dock as an opt-in placement of the existing floating presentation controller. Use a borderless, non-activating, opaque dark panel at floating level. On an active, unmirrored built-in display with a safe-area inset, place the panel directly below the housing, centered between the auxiliary top areas when both are available. With no safe inset, place the panel at the visible-frame top center, 6 pt below the visible menu bar. If the built-in display is absent or mirrored, use the selected display and label the placement as a top-of-display fallback. Never use the menu-bar areas beside the housing or allow vertical dragging.

Use a 44% display-width default clamped to 360–760 pt, three visible text lines clamped to 2–5, and a zero horizontal nudge. Derive the strip height from the current presentation line advance. Keep its compact controls below the text strip. Persist width, line count, and horizontal nudge by display UUID. Screen changes recompute from fresh `NSScreenNumber`-identified display descriptors and current safe-area geometry.

Camera Dock replaces the current presentation surface and reuses its session, immutable snapshot, guide anchor, Follow Voice and Timed Scrolling behavior, keyboard routing, and explicit exit/return path. Committing pauses the session and shows Camera Dock in a visible paused Ready state; Play starts the take. The inspector presents first-use guidance as a nonmodal disclosure. It does not access the camera or microphone. Explain that screen recordings include the prompt and that external camera placement is assumed; show a hint when the built-in camera may be on another display. If the display disappears or placement becomes invalid, pause and retain the position without opening a fallback surface automatically.

## Consequences

Pure Foundation geometry and preference tests cover notched, no-inset, external negative-origin, clamping, malformed, and unavailable cases. Native tests cover panel configuration, playback/timed-session continuity, and return to the prior surface. These checks prove arithmetic and application wiring only; they do not establish physical housing clearance, full-screen recording behavior, gaze, VoiceOver usability, accessibility appearance settings, Get Info compatibility behavior, or macOS 14 runtime behavior.

Do not add `NSPrefersDisplaySafeAreaCompatibilityMode` until the compatibility-mode hardware audit is complete. Keep all M1–M14 hardware/runtime checks pending in the manual test plan.

## Staged-flow implementation refinement

The live Dock and the editor placement preview consume one immutable `CameraDockLayout` produced by CueFlowCore. The preview uses the target screen's true display aspect ratio and draws its visible menu-bar band, an estimated housing only when a built-in safe-area inset exists, and the exact Dock rectangle from that layout. Its caption distinguishes built-in placement, built-in no-inset fallback, and external-display fallback; it says the camera position is assumed on fallback displays and can note that the built-in camera may be elsewhere.

The attached style is flush with the safe-area edge, pure opaque black, has square top corners and 14 pt lower corners, and has no shadow. No-inset and external fallback panels sit 6 pt below `visibleFrame.maxY`, use a near-black background with 14 pt corners, and have a subtle shadow. Both styles use the same placement frame shown in the map.

Committing from Preview, Floating, or Output captures the shared guide anchor, prior surface, and prior play state. CueGlass pauses the one session, closes the prior surface, and shows Camera Dock in a visible paused Ready state. Play starts it. Exiting closes the Dock and restores the saved surface and play state. The Output inspector presents first-use guidance as a nonmodal callout and keeps a capture disclosure visible while Camera Dock is selected. The capture wording is limited to screen recordings and full-display shares; no claim is made about single-app window sharing.

Automated geometry, map, callout, surface-transition, and styling tests cover this implementation. They do not satisfy any physical or runtime observations in M1–M14.

## Safe-area geometry recovery refinement

`NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea` refine the horizontal anchor when both rectangles are valid and ordered. If either rectangle is missing or inconsistent, center the panel on the display while keeping its top edge at the valid safe-area boundary; auxiliary-area metadata must not reject a fit that remains below the camera housing. If the safe-area boundary lies above the visible-frame top, use the detached top-of-display position below the visible frame. If the panel cannot fit below an in-frame safe-area boundary, reject the placement rather than moving it into the housing area. The live panel and placement map continue to use the same computed layout.

Core regressions cover incomplete/reversed auxiliary rectangles and the detached fallback. These tests establish arithmetic only; owners still need to observe housing clearance and the placement map on notched hardware.

## Notch-integrated surface refinement (2026-10-16)

The owner clarified that the Camera Dock should visually join the MacBook notch, following the integrated black surface used by notch-focused apps. On a built-in, unmirrored display with a valid safe inset, CueGlass now anchors the whole opaque panel to `screen.frame.maxY`; the black backing occupies the camera-safe band, while the prompt and controls begin strictly below that band. The attached panel uses a window level above the menu bar while active. The text viewport can be nudged without moving the centered backing away from the camera area. The no-inset and external-display fallbacks keep their visible-frame placement and lower window level.

If `safeAreaInsets.top` is zero but both auxiliary top areas are present, finite, top-aligned, and ordered, CueGlass derives the camera band from their shared lower edge. A single, misaligned, or otherwise invalid area does not imply a notch; the interface keeps the explicit top-of-display fallback label. The geometry exposes both the full black panel frame and the usable content frame so tests can assert that visible content stays below the housing even while its black backing joins the notch.

The editor's main stage always remains a live prompt preview. The display map and placement controls live together in the Camera Dock inspector disclosure, so opening the Dock no longer replaces the script preview with a monitor diagram.

The implementation was informed by [another.notch](https://github.com/jinkun1998/another.notch) and [Sapphire](https://github.com/cshariq/Sapphire). Both use app-owned top-anchored surfaces and display safe-area geometry rather than a public Dynamic Island API. CueGlass uses an independent static panel and its own geometry; no reference code is copied.

Core and native tests cover the backing/content separation, auxiliary-area inference guard, menu-bar window level, and the editor preview remaining active. Hardware validation of the visual seam, text clearance, menu-bar overlap, recording visibility, and camera gaze remains pending under M1 and M15.

## Notch silhouette, centred reading line, and motion refinement (2026-10-17)

The owner rejected a tray that stops at the bottom of the menu bar ("wtf is this?", screenshot of the gap beside the housing) and asked for the Sapphire treatment. The attached Dock is therefore one black surface whose top edge is the display's top edge: it covers the housing and the menu-bar band for the width of the tray, with concave ears of up to 24 pt that flare outward along the top edge and 32 pt lower corners. This supersedes the earlier rule against using the menu-bar band beside the housing for the surface itself; prompt text and controls still never enter that band, and the panel keeps the window level above the menu bar. Parked, the surface is a pill from the display top to a 14 pt chin under the housing, 104 pt wider than the housing, with 10 pt ears. The panel frame is widened by the ear radius on both sides so the ears stay inside the window.

With the surface covering the band, the attached Dock's controls move into it: Close and Play sit in the band left of the housing, the status text and the Adjust menu right of it, all inside the current silhouette, and the 44 pt controls band below the text is gone, so the open tray is text only. The parked pill keeps Play and Adjust at its ends. The detached fallback keeps its controls band below the text. This replaces the earlier "controls below the strip" rule for notched displays at the owner's request ("integrate controls pane to notch island").

The Dock strip holds exactly the chosen number of lines plus 8 pt margins, and the reading line sits in its vertical centre: CueFlowCore reports a per-layout `guideFraction`, and the operator passes it as the guide fraction of both the live Dock viewport and the editor preview while the Dock is active. Inside the Dock, paragraphs are centred, the text column is 86 % of the strip, the reading-guide line and triangles are hidden, and an overlay keeps the reading line at full brightness while dimming the lines above and below to 50 %; the strip's top and bottom edges fade over 14 % of its height so lines enter and leave softly. The session's logical size remains the full viewport; anchors, measurement, Timed Scrolling, and Follow Voice are unchanged.

State transitions animate the mask path with two springs read off the Sapphire configuration: opening at a 0.4 s response with a damping fraction near 0.6 (a hint of overshoot), closing at a 0.3 s response critically damped, both bounded to 0.3–0.6 s. Opening lands the empty surface first and then resolves the content from blurred to sharp over 0.3 s; closing hides the content in 0.1 s and shrinks the surface after a 0.08 s delay. Reduce Motion keeps a 0.15 s crossfade with no shape motion and no blur. Committing the Dock reveals it from the chin. Collapse to Notch pauses playback and parks it; hover peeks a parked Dock; Play opens it and removes the controls band from the tray while playing. Geometry changes (width, lines, nudge, display) still resize the panel without animation.

## Emulated island on displays without a notch (2026-10-17)

The owner showed Sapphire drawing its island on a display without a notch and asked for the same. By default CueGlass now draws the attached island on every target display: around the hardware housing when the display reports one, and otherwise around an emulated housing sized from the display width (185 × 32 pt at a 1728 pt reference, clamped), at least as tall as the menu bar, centred on the display. The placement map labels the emulated case "notch island · camera position assumed"; the hardware case stays "notch integrated". The stored `forceNotchAttachment` preference keeps its name: `false` is the only opt-out and restores the plain tray below the menu bar with its own controls band; `nil` and `true` both draw the island. The Camera Dock inspector exposes the opt-out as "Notch island on displays without a notch", persisted per display with the other placement preferences. The earlier "top-of-display fallback by default" decision is superseded for the island; the fallback itself is unchanged when chosen.
