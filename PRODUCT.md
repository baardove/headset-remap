# Product

## Register

product

## Users

The Mac owner uses a Jabra Evolve3 75 with a Link 390 adapter. They prefer Codex and also want Grok, Siri, and other configurable actions. The app runs in the menu bar and should be quick to understand while doing other work.

## Product Purpose

Headset Remap turns the headset's Teams button into a configurable action. Saved profiles preserve the complete setup so switching agents requires choosing a profile, not re-entering settings. Preserve the already-tested standalone headset handshake and immediate activation.

## Brand Personality

Plain, calm, practical. This is an existing native macOS utility, not a marketing surface. Use the familiar AppKit controls and system typography already present in the app.

## Anti-references

The user explicitly rejected exposing all technical details at the top level. Avoid raw HID codes, dense diagnostic output, repeated setup instructions, and competing management buttons in the everyday view.

## Design Principles

- Make selecting a saved profile the main everyday interaction, with quick access from the menu bar.
- Provide per-profile global keys for switching the headset or running an action without switching.
- Show the selected action and readable readiness state at a glance.
- Keep detailed configuration under Advanced and raw traffic in Debug.
- Preserve edits deliberately when switching profiles.
- Keep the current working configuration during migration.

## Accessibility & Inclusion

Retain AppKit's keyboard navigation, system appearance support, standard labeled controls, and selectable diagnostic text. Use text as well as color for readiness and errors. Keep advanced controls accessible without requiring knowledge of HID identifiers.

## Approved UI direction (2026-11-07)

The user approved combining draft A's menu bar popover, draft C's main launcher, and draft B's quieter settings editor. The launcher displays one row per profile, a selected-headset indicator, and separate direct Run buttons. Settings retains the detailed editor under Advanced, with raw input in Debug. Grok targets the installed Grok Bot desktop app, not the website.

## App identity

The user renamed the app to **Headset Remap** and chose a headset app icon. The existing preferences domain remains unchanged so saved mappings, profiles and shortcuts carry forward.

## Button action policy

The user clarified that internal headset functions should remain intact. Assign extra actions to any input the adapter exposes, with per-profile button configuration and custom inputs. Play/pause should be able to ignore extra actions during playback and trigger them when audio is idle. Audio rules use playback activity, not a claim to detect the headset’s physical power state.

## Agent ordering

Siri is the immutable first agent and always enabled. Codex, Grok Bot, Claude, Hermes and OpenClaw are initial configurable entries. Users can enable/disable, add, remove and reorder other agents. Only enabled agents receive sequential numbers and global shortcuts. The compact popover uses 12 px outer padding, as explicitly requested.

Agent reordering uses up/down chevrons in each row; Siri’s row controls are disabled.

Previous/next shortcuts cycle through enabled agents and show a large non-activating label beside the menu bar icon. Reorder chevrons are side by side in compact rows.

Secondary actions run automatically after the primary agent action on a headset press. Their UI menus are optional manual controls; enabled steps execute in configured order. Configure integrations per agent; keyboard actions must verify the target app is frontmost.
