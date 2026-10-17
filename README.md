# CueGlass

CueGlass is a native macOS teleprompter for talks, presentations, and recordings. It keeps your script at eye level while you speak, with a clean presentation view and controls close at hand.

## What you can do

- Open and edit plain-text, RTF, and CueGlass documents.
- Set your reading pace in lines per minute and adjust typography without replacing the document’s original formatting.
- Present full-screen on a selected display or use a floating prompter window.
- Opt into a compact Camera Dock: a black island anchored to the top of the display around the camera housing (the MacBook notch, or an emulated housing on other displays), with the prompt below the housing band and a plain-tray opt-out.
- Use a reading guide, optional mirrored text, countdowns, timed scrolling, and keyboard or clicker controls.

## Try CueGlass

Download the current build from [GitHub Releases](https://github.com/gAmUssA/CueGlass/releases). The universal macOS app supports Apple silicon and Intel Macs. The current release is unsigned and has not been notarized, so macOS may prevent it from opening. If that happens, wait for a signed and notarized release; this project does not provide instructions for bypassing Gatekeeper.

CueGlass is built for macOS 14 and later; full runtime verification on macOS 14 is still pending. The initial release is local-first: documents stay on your Mac, and iCloud synchronization is planned for a later milestone.

## Documents

Open `.txt`, `.rtf`, or `.cueflow` files from Finder or from the app. CueGlass preserves the imported source while applying presentation typography separately. Some advanced RTF elements may be simplified in the teleprompter view; the original source remains available in the document.

## For contributors

Build and test instructions, implementation notes, and agent guidance are in [AGENTS.md](AGENTS.md). Product architecture and current verification limits are in [Architecture](docs/ARCHITECTURE.md), [Implementation status](docs/IMPLEMENTATION_STATUS.md), and the [Manual test plan](docs/MANUAL_TEST_PLAN.md). Design research and recorded technical decisions are collected under [`docs/design`](docs/design/README.md) and [`docs/adr`](docs/adr/README.md).
