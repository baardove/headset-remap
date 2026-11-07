# Code review — 7 November 2026

Review covers HID routing, selected device handling, settings/migrations, action execution, voice state detection, permissions, lifecycle, UI save paths, and publication changes. The findings below record the initial review. The subsequent user-authorized fixes are described under Resolution; live installation remains deferred.

## Findings

1. **P1 — Delayed secondary actions outlive cancellation.** `Sources/AgentActionExecutor.swift:9` schedules an unconditional closure. `Sources/main.swift:1372` checks profile/device/paused state before entering the executor, but none of those checks run after the secondary action's configurable delay. Switch profile or headset, disable the agent, or start learning during that delay: a URL or Shortcut still executes; a keyboard action can still execute if its old target remains frontmost. Carry a cancellation generation/validity callback into the executor and check immediately before dispatch. Evidence: source tracing; no live shortcuts triggered.

2. **P2 — Audio conditions use every Jabra output instead of the selected headset.** `Sources/AudioActivityMonitor.swift:38` collects all Jabra output devices, and line 47 treats playback on any as active. Selecting Link 380 for buttons while Link 390 plays audio can suppress Link 380's audio-idle mapping or allow an audio-active mapping for the wrong headset. Connect selection to the audio probe or explicitly offer a separate audio-device scope. Evidence: source tracing; concurrent hardware playback was not tested.

3. **P2 — Two adapters of the same model share debounce.** `Sources/HeadsetButtons.swift:37` keys triggers by button and product ID, while `Sources/ButtonMapping.swift` keeps one last-fire timestamp per trigger. With All connected headsets, a press on adapter B within 350 ms of adapter A is dropped even though the physical locations differ. A read-only synthetic replay returned one match for A and zero for B 100 ms later. Include physical device identity in the trigger key while continuing to deduplicate interfaces for that same device.

## Other observations

Removing a selected secondary action leaves its stored selection pointing to the deleted UUID; automaticActions then returns an empty array. A synthetic reproduction confirmed this. Reset that selection to None when deleting and make the UI state explicit.

The Grok Bot installation identifies as `com.anysphere.sand`. Its bundled renderer has a Start voice chat control and an internal voice action, but inspection did not establish a public external voice-start shortcut or URL. No shortcut was invented and no call was started. A supported command/shortcut (or a separately designed accessibility-button action) is needed before adding a reliable preset.

## Verification and limits

- Existing 204 portable mapping/profile/audio-rule checks passed before this documentation/credits-only update.
- Current Swift source typecheck passed; synthetic checks reproduced shared debounce and stale action selection without touching preferences or hardware.
- Earlier actual hardware evidence: Evolve2 65 / Link 380 opened Codex with Voice Chat; Evolve3 75 / Link 390 reported Teams input and opened Codex with standalone mode.
- No new physical button, voice-start/stop, permission, sleep/wake, or two-adapter playback tests were performed during the active call. Existing five Carbon and five voice-label test results do not prove live voice operation.
- About uses the native standard panel; new visual acceptance and installation remain deferred until after the call.

## Resolution

All three findings and the stale deleted-action selection are fixed in the follow-up source update:

- A shared cancellation generation invalidates pending primary/secondary work on configuration, device, learning and sleep transitions. The executor checks it after its delay and after opening an app, before dispatching any secondary action. Headset actions also recheck the mapped-actions pause state.
- Audio conditions use the selected adapter's USB model and serial identity. Unknown/disconnected identity fails closed; All connected headsets retains aggregate behavior. The quiet-state gate resets when device selection changes.
- Debounce keys include physical location, preserving suppression across duplicate interfaces on the same adapter while separating same-model adapters.
- Deleting the selected secondary action explicitly selects None.

Validation: 214 portable checks and six real-executor cancellation checks with a fake external launch boundary pass. The tests do not open apps, send shortcuts, change preferences, or interact with the active call. Hardware playback across two adapters, additional physical buttons, and the new About panel still need later live acceptance.
