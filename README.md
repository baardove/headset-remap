# Headset Remap for macOS

Turn your Jabra headset button into a launcher for your preferred assistant, with optional follow-up actions such as Voice Chat. Native Swift menu-bar app for macOS 13 or later, supporting Apple Silicon and Intel.

### iPhone feasibility test

The separate [Jabra Button Probe for iOS](iOS/README.md) checks whether an iPhone exposes headset button signals through Bluetooth LE notifications or media commands. It includes timed comparisons and a shareable diagnostic report. This is a test app, not an iOS remapper; Teams-button compatibility still requires physical headset testing. Open `iOS/JabraButtonProbe.xcodeproj` in Xcode to build it.

## Get started

1. Clone this repository and run `./build.sh` (requires Xcode Command Line Tools).
2. Open `build/Headset Remap.app` and grant Input Monitoring when prompted. Keyboard actions also need Accessibility permission.
3. Select your headset adapter in the Launcher, then open the gear to configure agents, primary actions and secondary actions.
4. Learn the desired headset button and test your action. Start at Login is optional.

### Verified compatibility

| Headset and connection | Observed working behavior |
| --- | --- |
| Jabra Evolve2 65 via USB Link 380 | Captured Teams-button presses; opened Codex and ran the Voice Chat secondary action. User confirmed voice started. Standalone handshake acknowledged. |
| Jabra Evolve3 75 via USB Link 390 | Repeated Teams-button events with Teams running; Codex activation with Teams closed using the standalone handshake. |

These results apply to the tested devices and firmware, not the entire Evolve2 or Evolve3 families. Other Evolve2/Evolve3 models, other adapters, wired connections and direct Mac Bluetooth are **untested**. Button learning may support them, but compatibility is not established. Mute, volume and other buttons require their own mapping and verification; the Teams-button result does not verify every control. Microphone-arm remapping is experimental and currently unassigned. Selecting a headset here controls button input; it does not change macOS audio routing.

## Credits and license

Based on [Saif Hassan (saiftheboss7)'s original Jabra mute-button remapper](https://github.com/saiftheboss7/jabra-evolve-mute-button-remapper-macos).

- Original creator: [Saif Hassan (saiftheboss7)](https://github.com/saiftheboss7)
- **Bård Ove Myhr**
- AI-assisted development: **OpenAI Codex**

Distributed under the [GNU Affero General Public License v3](LICENSE). Upstream license and provenance are preserved. Right-click the menu-bar icon and choose **About Headset Remap** for credits and a link to this README.

## Support development

If you find Headset Remap useful, you can [buy me a coffee on Ko-fi](https://ko-fi.com/baardove) to support its development. Support is completely optional. Thank you!

## Privacy and permissions

Headset input and settings are handled locally. Configured actions can open external apps, URLs or macOS Shortcuts. Diagnostic logs may contain device names, app targets and action names; review them before sharing. Ad-hoc development builds may require renewing macOS permissions after rebuilding.

## Navigation

The **Launcher** is for everyday use: select the agent the headset controls, run its configured action sequence with Play, and open setup with the gear button beside the headset selector. Play runs the primary action first, then the selected secondary action or checked sequence in order. Named actions remain available from the menu-bar popover. The current headset action sequence is shown below the agent list.

**Configuration…** is the single entry point for setup:

- **Agents & actions**: enable and reorder agents, choose their apps, and configure the actions that run after the headset opens them.
- **Headset buttons**: learn physical inputs and assign an additional action for each agent.
- **Advanced settings**: keyboard shortcuts, activation timing, and Teams compatibility.
- **Input diagnostics**: troubleshoot input detection and inspect logs.

Advanced and troubleshooting destinations are initially collapsed. Custom targets, timing, compatibility, and diagnostic details also stay behind disclosure controls. Setup screens show their location and a back button. Navigating replaces the visible setup screen and asks about unsaved changes before leaving. The action editor returns to **Agents & actions**; the other setup screens return to **Configuration**.

## Agent actions

Open **Configuration… → Agents & actions** from the headset menu bar icon:

- **Codex** — preferred initial action when its app is installed.
- **Grok** — launches or activates the installed **Grok Bot** desktop app.
- **Siri** — opens the installed Siri launcher.
- **ChatGPT**, another installed app, or any supported app/web URL.
- **Run a macOS Shortcut** — enter its exact name to run a custom agent or voice workflow.

Use **Test primary action** to verify the target, then **Save agent**. **Agent focus** defaults to a 0.5-second delay for the Teams button so the selected app activates after Teams processes its own button. Immediate and 1-second timings are also available. Teams may briefly appear; this shared-HID approach does not suppress its native response. The primary Open step activates its app; configured secondary actions can then start voice or another workflow. A Shortcut can perform a supported voice workflow. Shortcut execution passes the name directly as an argument, without a shell.

Settings are stored in the app's macOS preferences (`local.jabrateamsremap`). The original app has a separate identity. Start at Login is optional and disabled by default.

## Profiles and keyboard shortcuts

Left-click the headset menu bar icon for a compact profile popover. **Open launcher…** shows enabled agents with Play buttons for their configured action sequences. **Configuration…** opens the setup hub. **Agents & actions** manages apps and their secondary actions; **Headset buttons** handles button learning and assignments. **Advanced settings** contains keyboard shortcuts and collapsed timing/compatibility options. Raw reports are available under **Advanced & troubleshooting → Input diagnostics…**. Right-click the icon for the utility menu.

The agent catalog keeps Siri fixed as agent 1 and preconfigures Codex, Grok Bot, Claude, Hermes, and OpenClaw. Installed desktop apps start enabled. OpenClaw starts disabled on this Mac until an app, URL or Shortcut target is configured. The current working headset mapping is preserved. Each profile preserves its button binding, target, timing, and compatibility settings. Use **Configuration → Agents & actions** to enable, disable, add, rename, or remove agents. The up/down chevrons on each row reorder it. Siri cannot be moved, disabled, renamed or removed. Only enabled agents appear in the launcher and receive a number and global shortcuts. Reordering or changing enabled agents regenerates the numbered shortcuts. Unsaved edits prompt before switching. The last profile cannot be deleted.

Click a profile in the menu bar popover to switch the headset action. **Run … now**, launcher Play, the Run menu and Run keyboard shortcuts all execute the primary and configured secondary actions without changing the selected headset profile. They use each secondary action's delay, stop on errors or configuration changes, and ignore another Run on the same profile while its sequence is running. The dropdown also offers individual named actions. The app stays in the menu bar when its windows close; **Start at Login** is optional.

Initial global shortcuts (⌃ Control, ⌥ Option, ⌘ Command):

Run shortcuts execute the primary and configured secondary actions. Selection shortcuts only switch which agent the headset controls.

| Profile | Run its action directly | Switch headset to profile |
| --- | --- | --- |
| Siri (fixed) | ⌃⌥⌘1 | ⌃⌥1 |
| Codex | ⌃⌥⌘2 | ⌃⌥2 |
| Grok Bot | ⌃⌥⌘3 | ⌃⌥3 |
| Claude | ⌃⌥⌘4 | ⌃⌥4 |
| Hermes | ⌃⌥⌘5 | ⌃⌥5 |
| OpenClaw (disabled) | — | — |

Choose **Configuration → Advanced & troubleshooting → Advanced settings…** to customize the active agent's keys. Click a recorder, press the combination, and save. Escape cancels recording; Delete clears the assignment. Include Control, Option, or Command. Assignments must be unique across all profiles; unavailable system combinations are reported in Advanced and the log. Numbered shortcuts follow the enabled order (1–9, then 0 for agent 10). Agents beyond ten can use custom shortcuts. Siri’s shortcuts stay fixed. Reordering regenerates defaults, including any manually changed numbered shortcuts.

Direct keyboard/menu actions work without a connected headset and use no Teams focus delay. They use the saved configuration, not unsaved edits in Settings. The app registers only those combinations with macOS; it does not capture general typing or require Accessibility access for the global shortcuts. Keyboard labels refer to physical key positions using US key names.

### Previous / next agent

**Control+Option+Left Arrow** selects the previous enabled agent; **Control+Option+Right Arrow** selects the next. They wrap around the enabled list, skip disabled agents and do not launch the target app. A large label beside the menu bar icon shows the selected agent for about two seconds without taking focus. Change or clear these shortcuts under **Agents & actions → Advanced: agent switching shortcuts**. Each field saves after recording and rejects conflicts with other registered shortcuts.

## Secondary agent actions

Use **Configuration → Agents & actions → Edit secondary actions…**. **Open** stays the primary action. Choose **None**, an individual action, or **All checked secondary actions, in order** in the agent’s **Secondary action** dropdown. A headset press runs that selection after the primary action succeeds. For multiple actions, use the checkboxes and up/down controls to choose the steps and their order. Errors stop the chain. Add named choices such as **Voice**, **New chat**, or any custom workflow. Configure each with the target app's keyboard shortcut, exact UI button label, a URL/deep link, or a macOS Shortcut. The current Codex presets use Control+Command+V for Voice Chat (when available) and Command+N for New chat, matching the supplied app shortcut screenshot. Other agent-specific integrations remain configurable.

A secondary action can optionally open the agent first, wait a configurable 0–5 seconds, and have its own global shortcut. It can also be selected as an additional action in the **Buttons** screen. Incomplete actions are marked **needs setup** and cannot run. Disabling the parent agent also disables its action shortcuts.

Keyboard and UI-button actions require **Accessibility** permission for Headset Remap. They target only the configured desktop app while it is frontmost; if focus changes, the action is canceled. URLs and macOS Shortcuts do not use simulated keypresses. Global trigger shortcuts are rejected as target keypresses to avoid loops.

## Multiple Jabra headsets

The launcher and menu-bar panel show detected Jabra devices under **Use buttons from**. Choose one adapter or **All connected headsets**. This selection filters headset button actions and learning; it does not change the macOS audio device. The selected adapter is remembered, and disconnecting it does not silently switch to another. USB adapters report their own names rather than the paired headset model.

Buttons can keep one learned input per USB product, so a Link 380 and Link 390 can trigger the same configured action without replacing one another. In **Configuration → Headset buttons**, select the button and use **Learn another headset**. The saved-input menu identifies each headset or adapter. **Remove input** removes only the selected input. Save the button afterward.

Evolve2 65 / Link 380 Teams-button reports were captured on this Mac on 7 November 2026: USB product `0x24C8`, usage page `0xFF99`, usage `4`, report `155`, element `76`, press value `1`. The Link 380 also acknowledged the existing standalone handshake. Evolve3 75 / Link 390 uses product `0x2E57` with the same observed Teams-button element. These are observations of these devices, not a universal preset for every firmware or Jabra variant. Relearn if a device reports differently.

The [official Evolve2 65 manual](https://www.jabra.com/_/media/Jabra_VXi_Product-Documentation/Jabra-Evolve2-65/User-Manuals/RevD/Jabra-Evolve2-65_User-Manual_EN_English_RevD.pdf) documents connecting through Link 380 and identifies the dedicated Teams button as a feature of the Teams variant. Other buttons can be learned when the adapter exposes them. Direct Mac Bluetooth operation has not been verified.

## Buttons and additional actions

Open **Configuration → Headset buttons…**. Each profile has slots for Teams, microphone mute, microphone arm, play/pause, volume up/down, call/answer, and voice assistant. Add custom slots for any other input your adapter exposes. Select a button, click **Learn input**, press and release that button, choose its press event, and save an additional app, URL or macOS Shortcut action. Existing Teams mappings migrate automatically.

These are **additional actions**. Headset firmware, the operating system and other apps may still perform the original action. This app does not suppress the original event. Some internal controls and gestures never reach the USB adapter and therefore cannot trigger an added action. Raw reports that do not expose a scalar button value need a device-specific decoder.

The **Microphone arm** slot is unassigned until learned. If the boom and mute button expose the same signal, configure only one slot; duplicate assignment is rejected. Native mute/unmute behavior remains intact.

Each button has an audio condition: **Always**, **Only when headset audio is idle**, or **Only while headset audio is active**. Play/pause defaults to idle-only for its extra action. The rule checks playback-stream activity on Jabra output devices, not the physical headset power state. It waits two quiet seconds before declaring idle so the act of pausing a movie does not immediately trigger an idle-only action. Rules use the sampled state at the button press; direct keyboard and launcher Run actions remain unconditional.

Audio activity detection uses Core Audio process/output metadata on macOS 14.2+. It records no microphone or system audio. Open but silent playback streams may still count as active. On older macOS or when the headset route is unavailable, state is unknown and conditional extra actions stay inactive. The Buttons screen shows the current state.

## Learn the Teams button

1. Connect the headset through its Link 390 USB adapter.
2. Launch the app and grant **Input Monitoring** in System Settings → Privacy & Security.
3. Open **Configuration → Headset buttons…**, select **Teams**, and click **Learn input**.
4. Press and release only the Teams button, then click **Stop learning** (or wait 15 seconds).
5. Select its **press** event from the captured signals. This is usually value 1; some devices use another value. If there are several candidates, use Debug Input to compare press/release events and test candidates individually.
6. Select your agent/action and click **Save button**. Debug Input can stay open while you test the mapped action. Keep **Run mapped actions** checked.

Hardware testing on the Evolve3 75 / Link 390 confirmed repeated Teams-button events with Teams running. A separate local handshake test then confirmed that the button also activates Codex with the real Teams app closed. The app includes that handshake as an optional **Use Teams button without Microsoft Teams (experimental)** mode.

The observed binding is USB product `0x2E57`, usage page `0xFF99`, usage `0x0004`, report 155, element 76, press value 1. It is saved in this Mac's preferences. Other installations should learn their own button. Allow four seconds after connecting the adapter before pressing the button; the app ignores initialization pulses during that interval.

## Standalone Teams-button mode

Enable **Use Teams button without Microsoft Teams (experimental)** under **Advanced settings → Advanced: timing & compatibility** and save. This sends a local USB idle-client handshake (version, capabilities, locale/time and no-pending-notifications) and refreshes it every ten seconds. No Microsoft account, sign-in, network request, meeting or call is created. The debug status shows whether the handshake is active or failed.

The mode automatically pauses when the real Microsoft Teams app is running, then resumes after it closes. It reconnects after USB changes and sleep/wake. Turning the option off or quitting the app stops the keep-alive; reconnect the adapter if you need to clear its retained session state immediately. This is an experimental compatibility implementation, not a full Teams/ASP client. Verified on 2026-11-07 with the integrated app: repeated physical Teams-button presses activated Codex while Microsoft Teams and the temporary probe were both stopped. The user confirmed both presses worked. Automatic handshake after a fresh USB unplug/replug and after sleep/wake is implemented, but those lifecycle paths are not yet independently verified on hardware.

Learning maps scalar HID inputs by USB product, usage page, usage, report ID, element cookie, and value. A vendor report that only appears as raw bytes needs a decoder based on the capture. Relearn if a firmware update changes the element layout. The device is shared with other applications; this does not guarantee that Teams or firmware will stop responding to the same button.

The upstream mute/Music controls and forced call mode are **off by default**. Enable them explicitly in **Advanced settings** if wanted. This avoids forcing the headset into a call merely to use its Teams button.

## Debug input

Choose **Configuration → Advanced & troubleshooting → Input diagnostics…**, or **Troubleshooting → Debug Input…** in the menu bar. It displays:

- `DEVICE`: connected Jabra HID interfaces and USB product IDs.
- `ELEMENT`: available input usage pages, usages, report IDs, cookies, and bit sizes.
- `VALUE`: decoded scalar input values, including vendor-defined usage pages.
- `RAW`: input report ID, length, and hexadecimal bytes (up to 256 per report).

**Input logging and mapped actions are independent.** Use Pause/Resume Logging to control only the log. Uncheck **Run mapped actions** for a passive test; learning always suppresses actions. The status line shows permission, connected interfaces, report count, and time since the last report. `BUTTON matched`, `ACTION started`, and `ACTION completed/failed` entries are written even with detailed logging paused. Use Clear, Copy Log, or Save Log to collect diagnostics. Only Jabra USB devices are monitored for input reports. Keyboard shortcuts register specific combinations with macOS; general typing is not captured. The window keeps the latest 2,000 lines. Logs also go to `~/Library/Logs/JabraTeamsRemap.log`, rotating at 256 KB.

From a terminal, with any existing instance quit:

```sh
"./build/Headset Remap.app/Contents/MacOS/HeadsetRemap" --debug
```

This prints input to the terminal and opens the debug window. Mapped actions remain enabled with `--debug`. Uncheck **Run mapped actions** if you only want to observe input. Quit and relaunch without `--debug` to turn off detailed input logging. If no input appears, verify Input Monitoring, the USB connection, and whether another application owns the device.

## Build and run

Requires Xcode Command Line Tools:

```sh
./build.sh
open "build/Headset Remap.app" --args --settings
```

Outputs a universal Apple Silicon/Intel app and `build/Headset-Remap.zip`. The app is locally signed, not notarized. If macOS requests it, use Finder's right-click → Open workflow. The build script reuses `JabraMicMute Signing`, or the sole available Apple Development certificate, to preserve the app's permission identity between builds. Set `HEADSET_REMAP_SIGN_IDENTITY` to choose a certificate explicitly; otherwise ambiguous/missing certificates fall back to ad-hoc signing. Switching from ad-hoc to stable signing requires renewing this app's grants once. If the debug window reports permission missing even though the System Settings switch is on, quit the app, run `tccutil reset ListenEvent local.jabrateamsremap`, reopen this exact build, and grant access again. This resets only this app’s Input Monitoring permission.

Tests for press/release behavior, debounce, device isolation, profile migration, shortcut conflicts, preferences, and target validation:

```sh
swiftc Sources/ButtonMapping.swift Sources/ButtonProfiles.swift Sources/HeadsetButtons.swift Sources/ButtonAvailability.swift Sources/HeadsetPhysicalControls.swift Sources/HeadsetDevices.swift Sources/AudioActivityRules.swift Sources/AgentSecondaryAction.swift Sources/AgentActionPresets.swift Sources/AutomaticAgentActions.swift Sources/KeyboardShortcut.swift Sources/TeamsProtocol.swift Tests/main.swift -o /tmp/jabra-mapping-tests
/tmp/jabra-mapping-tests
```

Carbon registration/dispatch checks (runs no agent actions):

```sh
swiftc Sources/ButtonMapping.swift Sources/ButtonProfiles.swift Sources/HeadsetButtons.swift Sources/HeadsetDevices.swift Sources/AudioActivityRules.swift Sources/AgentSecondaryAction.swift Sources/AgentActionPresets.swift Sources/AutomaticAgentActions.swift Sources/KeyboardShortcut.swift Sources/GlobalHotkeys.swift Tests/Hotkeys/main.swift -o /tmp/jabra-hotkey-tests
/tmp/jabra-hotkey-tests
```

`--preview` opens Configuration without starting the HID listener. Use `--settings` to open the advanced settings screen directly. Add `--launcher` for the profile launcher, or use `--preview-popover` to inspect the menu bar popover. Preview mode leaves global shortcuts unregistered so an existing running copy retains them.

## Source files

- `Sources/main.swift`: CoreAudio, Jabra HID listener, menu bar, lifecycle and logging.
- `Sources/ButtonMapping.swift`: persisted action configuration and button matching.
- `Sources/ProfilePopover.swift`: compact menu bar controls.
- `Sources/ProfileLauncherWindow.swift`: all-profile launcher.
- `Sources/AgentSecondaryAction.swift`: named action configuration and references.
- `Sources/AgentActionsWindow.swift`: per-agent secondary action editor.
- `Sources/AgentActionExecutor.swift`: guarded secondary action execution.
- `Sources/AgentUIButton.swift`: exact accessible-button matching and guarded presses.
- `Sources/AgentSwitchHUD.swift`: non-activating agent selection feedback.
- `Sources/AgentsWindow.swift`: dynamic agent catalog, enable switches and ordering.
- `Sources/HeadsetButtons.swift`: per-button mappings and independent edge routing.
- `Sources/ButtonsWindow.swift`: all-button learning and additional actions.
- `Sources/AudioActivityMonitor.swift`: playback activity metadata.
- `Sources/AudioActivityRules.swift`: conditional actions and idle settling.
- `Sources/AgentApplications.swift`: installed agent app resolution, including Grok Bot.
- `Sources/ButtonProfiles.swift`: saved profiles, migration and shortcut conflict validation.
- `Sources/KeyboardShortcut.swift`: portable key bindings and labels.
- `Sources/GlobalHotkeys.swift`: macOS global shortcut registration and native key recorder.
- `Sources/ConfigurationWindow.swift`: setup hub, section headings, navigation and collapsed advanced controls.
- `Sources/ButtonSettingsWindow.swift`: keyboard shortcuts, activation timing and compatibility settings.
- `Sources/InputDebugWindow.swift`: live input capture and export.
- `Sources/TeamsProtocol.swift`: tested local handshake framing.
- `Sources/TeamsCompatibility.swift`: optional standalone keep-alive and lifecycle handling.
- `Tests/main.swift`: hardware-independent mapping and configuration checks.

Upstream commit at download: `0dac819`. See [upstream documentation](https://github.com/saiftheboss7/jabra-evolve-mute-button-remapper-macos#readme) for the original mute/Music implementation. This local adaptation retains the upstream AGPL-3.0-or-later license; see [LICENSE](LICENSE).

### Select the automatic secondary action

In **Agents & actions**, use the **Secondary action** dropdown to choose **None**, one configured secondary action, or **All checked secondary actions, in order**. Save the agent. The selection applies to physical headset activation, launcher Play, **Run … now**, the Run menu and Run keyboard shortcuts. **Test primary action** in settings still tests just the primary step.

For Codex configurations that include Voice, the headset trigger first looks for the installed app's accessible End Voice/Stop voice chat control. When present, it presses that control and skips the launch/action chain. This detects the app's exposed voice state, not merely a remembered last click. Accessibility permission is required.

For **Grok Bot**, add **Voice** in **Edit secondary actions…**. The preset opens Grok, waits 0.6 seconds, locates its exact **Start voice chat** button through macOS Accessibility, and clicks the button's current center. Grok accepts `AXPress` without necessarily opening voice, so this integration uses a real pointer click. It checks the element under the pointer before clicking and confirms the voice panel's **Hang up** button before reporting success. While voice is active, another headset press, Play/Run, or the Voice action clicks **Hang up** and confirms the panel closed. For a headset/Run trigger this skips the primary and remaining actions. Only profiles with Grok Voice selected in their configured sequence get this toggle behavior. Select the Voice action in the agent's **Secondary action** dropdown and save. **Start voice input** is a separate dictation control.

The **Press a button in the agent** action type also accepts another exact accessible button label. Other controls use `AXPress`. All button actions require the target app in front and one enabled matching button in its focused window. They cancel if inspection is incomplete, the label changes, or focus/configuration changes. The Grok click also cancels if the button is covered or has invalid bounds; no fixed screen coordinates are stored.

Read-only button verification (requires Accessibility permission, does not open Grok or start voice):

```sh
"build/Headset Remap.app/Contents/MacOS/HeadsetRemap" --probe-ui-button com.anysphere.sand "Start voice chat"
```

### Screenshot action presets and stacks

Codex includes Open your dot, New chat, New temporary chat, New standalone chat, Open side chat, Voice Chat, End Voice Chat, Toggle Voice Chat microphone, and Toggle Voice Chat audio. The supplied screenshot bindings are used, including Command+Period for your dot and Control+Command+V for Voice Chat. Newly added presets are unchecked, so they do not all fire at once.

Choose **All checked secondary actions, in order** in the agent’s **Secondary action** dropdown. In **Edit secondary actions…**, check the steps to include and move them into order with the arrows. For example, check **Open your dot** and **Voice Chat**, leaving the chat-creation and voice-ending actions unchecked. Each step’s delay controls the wait before it runs. Selecting a single action or None remains available.

## Other headset buttons and audio rules

The button editor already supports learning mute, play/pause, volume up/down, call/answer, voice assistant, microphone arm and custom slots. A slot name does not establish hardware support: learn and test a separately reported HID input before assigning an action. Only the Teams-button behavior described above has been physically verified for these two headset/adapter pairs. The boom arm remains unassigned; it may share a mute input or expose no usable independent event.

**Headset buttons** shows one exact-model diagram from Jabra's official overview illustrations. The catalog includes Evolve2 30, 30 SE, 40, 40 SE, 50, 55, 65, 65 Flex, 75, 85 and Buds, plus Evolve3 45, 65, 65 Flex, 75 and 85. Physical controls are numbered down the left side, then down the right; shared functions retain one number. The same numbers appear in the button list and debug window. The Evolve2 65 power/Bluetooth slider is at the bottom of its right earcup.

The app selects a model automatically when the selected input device reports an identifiable headset product name. For this setup, Link 380 defaults to Evolve2 and Link 390 defaults to Evolve3, as requested; this selects a series and is not proof of an exact paired model. When exact identification is unavailable, **Evolve2 / Evolve3** tabs and model tabs let you choose explicitly. The choice is saved for that individual adapter and restored when switching adapters. Tabs fit on one row when space permits and wrap in narrower windows. Only the current model's diagram is shown. The drawings identify physical controls, not proven remapping support. Each drawing links to its source manual; the source manifest is in `assets/HeadsetDiagrams/sources.json`.

Open **Button debug…** to check or uncheck available buttons independently for each exact model. Unchecking hides the button from that model's configuration list and disables its mapped actions across agents, preserving all learned inputs and saved actions. Rechecking restores them. The configuration list includes controls represented on that model; the microphone arm is shown only for models that have one. Unknown, unassigned adapters retain their existing behavior. **Live input…** opens the existing diagnostic tool for hardware testing. Model catalog coverage does not establish hardware remapping support for untested headsets.

Learning additional inputs does not suppress the headset's native volume, call or media behavior. Legacy mute/Music control is opt-in. Selecting one adapter also scopes audio conditions to that adapter's CoreAudio identity; if it cannot be identified, audio-dependent actions stay inactive rather than using another headset's state.

Delayed-action regression checks (fake launch boundary; no shortcuts or apps are fired):

```sh
swiftc Sources/ButtonMapping.swift Sources/ButtonProfiles.swift Sources/HeadsetButtons.swift Sources/HeadsetDevices.swift Sources/AudioActivityRules.swift Sources/AgentSecondaryAction.swift Sources/AgentActionPresets.swift Sources/AutomaticAgentActions.swift Sources/KeyboardShortcut.swift Sources/VoiceSessionState.swift Sources/GrokVoiceSession.swift Sources/AgentUIButton.swift Sources/AgentActionExecutor.swift Tests/Actions/main.swift -o /tmp/jabra-action-tests
/tmp/jabra-action-tests
```

## Voice activity indicator

The tray icon shows a light-orange badge with dark headphones while **Codex or Grok Bot** exposes an active voice-session control. Headset Remap checks both apps once per second, including sessions started or ended directly in either app and sessions in background windows. It restores the normal icon when neither app reports an active session; the tooltip names each app and distinguishes inactive from unavailable. Detection requires Accessibility permission. Codex recognizes English and Norwegian voice-control labels; Grok currently recognizes the observed English **Hang up** and composer controls. An incomplete or unknown UI never proves that voice is active.

For a profile configured with Voice, the launcher changes its Play button to **Stop** and shows **Voice active** while that agent reports an active session. Stop checks the current session again and never starts a new one if the displayed state became stale. Grok is brought forward before stopping; the click waits briefly if the window is still moving into view. It retries only before a click has been sent, then confirms that the call ended.

The launcher is 430 points wide. In both launcher and menu-bar popover, the headset dropdown occupies about two-thirds of its row. The popover places launcher and configuration icons beside it; the launcher places its configuration gear there. The old bottom navigation buttons are removed.
