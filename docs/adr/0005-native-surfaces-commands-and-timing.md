# Title

Single presentation surface, app-local controls and timing aids

# Status

accepted

# Date

2026-10-13

# Context

R10/R11/R14–R16 require single-display floating presentation, hidden-operator transport, keyboard-emulating clickers, countdown/timed reading and static reading aids. The owner rejects dense desktop control rows. NSDocument, immutable takes and one shared host-time timeline remain mandatory. This extends [0004](0004-lines-per-minute-direction-and-schema.md) and qualifies ADR 0002's paused typography rule only for surface switches and end-of-live-resize.

# Decision

Use one active surface (fullscreen output or floating panel), otherwise preview. Switching surfaces and finishing a floating live resize capture/restore the anchor and preserve running/paused state; typography changes remain paused. Live resize scales old logical content, with one coalesced relayout at its end. Use native NSPanel for floating presentation and a small Controls HUD. Never place Controls over selected fullscreen output; choose another safe display or hide it with menu/keyboard recovery. Persist relative frames per display and clamp restoration. Apply real whole-window opacity 30–100% (85% default), separate text-panel opacity and a composited contrast warning below 4.5:1. Click-through is optional while playing and always clears on pause.

Use a Foundation CommandMap with sensible default aliases, app-local key routing, conflict/reserved-shortcut validation, local versioned persistence and reset. Text/control/inspector responders retain ordinary editing. All primary actions have native menus and accessible labels. No global/local event monitor is installed.

Count down on host time with a frozen timeline, cancellation and mirrored digits. Elapsed counts only playing intervals; remaining follows direction and actual bounds. Timed Scrolling solves to the actual forward end, rejects unsupported durations/pace and re-solves for remaining playing duration after navigation/relayout. Manual pace or direction changes disable it visibly. Hold at either outward bound; Restart returns forward/start/paused and resets elapsed. UI readouts update at 4 Hz; frames only sample/scroll and update changed countdown digits.

Guide styles, opacity, edge gradient and text-panel opacity update static presentation layers without text layout; margins use the anchor path. Hide-while-playing fades chrome after inactivity and restores on pause/command/pointer movement. Respect Reduce Motion/Transparency and Increase Contrast. Persist the [research/concept](../design/README.md) separately from actual evidence.

# Consequences

No hidden second timeline/session or cloud-backed live controls exist. Clickers must target the app or an app window must be key. Hardware validation remains necessary for fullscreen-app floating visibility, click-through recovery, optical output, accessibility and sustained performance. A concept or cached bitmap does not prove a real-window/hardware visual pass.
