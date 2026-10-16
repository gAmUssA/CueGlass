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
