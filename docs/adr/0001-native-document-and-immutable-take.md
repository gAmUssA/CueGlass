# Title

Native document ownership with an immutable take and a pure timeline

# Status

accepted

# Date

2026-10-13

# Context

The app must preserve authored RTF, play continuously across display refresh rates, and accept iCloud document updates without replacing text mid-take. A single shared mutable text storage would couple editing, cloud reloads and presentation. A custom cloud save watcher would compete with document coordination.

# Decision

Use NSDocument for source/save/version lifecycle, a Foundation-only versioned codec and timeline package, copied immutable attributed snapshots for takes, and separate derived presentation styling. View-associated CADisplayLinks sample one timeline. Output supplies logical layout; preview scales it. Use FileManager's entitled iCloud container and actual resource metadata, with NSDocument Versions and Save a Copy for conflict recovery. Commit XcodeGen's deterministic spec and real project/shared scheme.

# Consequences

Core timing and validation are deterministic and hardware-independent. Paused/resumed takes remain stable under reload. Layout changes require anchor capture/restore and stay paused. Signing/container setup belongs to the owner. CADisplayLink smoothness, physical reflections, sandbox panels and two-Mac conflict UI require manual validation; compilation or simulated replacement is insufficient proof.
