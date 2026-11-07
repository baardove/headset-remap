# Verification, 7 November 2026

## Implemented

- Saved profiles, with the current hardware mapping and immediate activation preserved during migration.
- Per-profile global keyboard shortcuts: switch headset profile, or run an action without changing the selected profile.
- Grok targets the installed `/Applications/Grok Bot.app` (`com.anysphere.sand`).
- Approved combination of compact menu bar popover (A), launcher (C), and minimal settings editor (B). Detailed settings are collapsed; raw input stays in Debug.

## Evidence

- 91 portable mapping, protocol, profile, migration and shortcut-configuration checks passed.
- 5 native Carbon registration/dispatch checks passed, including held-key suppression and maintaining direct-action routing across active-profile changes.
- Universal arm64/x86_64 build produced. Signature verification checked separately on the final bundle.
- Native UI inspection: launcher lists Codex, Grok Bot and Siri; profile selection updates the visible active indicator; settings retain the learned Link 390 binding and immediate activation. Duplicate shortcut feedback was exercised in the UI.
- Grok Run action was exercised from the launcher with Codex selected. Log confirmed target and foreground bundle `com.anysphere.sand`; selected headset profile remained Codex.
- User confirmed both Control+Option+Command+1 (Codex) and Control+Option+Command+2 (Grok Bot) work with another app in front.
- Popover content was inspected through a native preview window because the UI automation tool does not expose the standalone NSPopover reliably. Production uses the same view controller anchored to the NSStatusItem.

## Hardware and permissions

Earlier in this session, the user confirmed repeated physical Teams-button activation with the real Teams app closed. Automatic USB-reconnect and sleep/wake recovery remain implemented but not independently hardware-verified. This UI/keyboard update does not change the handshake.

This build is locally ad-hoc signed. macOS requires renewing its Input Monitoring grant after the binary changes. Keyboard shortcuts do not depend on this permission; the headset does. Final headset confirmation remains dependent on that grant and a physical button press.

## Rename

Display name, bundle name, window titles and distribution changed to Headset Remap. The executable is HeadsetRemap; the bundle identifier stays local.jabrateamsremap to preserve preferences. The app icon now uses a headset symbol.

## Multi-button and audio rules

- 114 portable checks now cover independent button routing, copied mappings, conflicts, and idle settling. The 5 native Carbon checks still pass.
- Live Core Audio metadata detected an active playback stream on a Jabra output. No microphone or system audio was recorded.
- Buttons screen was inspected in the native app. Known slots, custom input support, learned Teams binding and idle-only play/pause default are visible. Extra actions remain unassigned on other buttons until the user learns and configures them.
- Actual play/pause/idle transitions and new physical button learning still need user hardware verification after renewing Input Monitoring for the final build.

## Dynamic agents

137 portable checks now include Siri pinning, enabling/disabling, reordering, contiguous numbering, shortcut reassignment, profile persistence and catalog migration. The 5 native Carbon checks remain separate. Installed app bundles were found for Codex, Grok Bot, Claude and Hermes. OpenClaw has no configured target on this Mac and remains disabled. Siri’s runtime action is fixed to the system Siri launcher. These new numbered shortcuts supersede the earlier Codex-1 / Grok-2 defaults tested above.

Native agent-manager checks confirmed moving Hermes updates its number and shortcut, disabling it removes both, and restoring it restores the numbered assignment. Siri edit/remove/reorder controls are disabled. The final UI uses per-row reorder chevrons.

## Cycle and secondary actions

- 161 portable checks and 5 Carbon checks pass, including cycle wraparound, secondary references, persistence, cloning and validation.
- Codex has separate Voice (Control+Shift+V) and New chat (Command+N) settings saved on this Mac, based on the fetched official OpenAI shortcut reference. Voice remains conditional on feature availability. Actual key delivery needs Accessibility permission and has not yet been exercised.
- The secondary-action editor was inspected natively. Unconfigured actions are disabled; keyboard actions check foreground identity before sending.
- Cycle shortcuts default to Control+Option+Left/Right, and a non-activating agent label is implemented beside the status icon. Manual HUD feedback is pending.

## Final running build

The signed universal Headset Remap build was restarted normally, and the log confirmed `input monitoring access: granted` followed by an active Link 390 handshake. Codex Voice and New chat settings were saved through the native editor. The Accessibility panel was opened with Headset Remap listed and its switch off; the user was asked to enable it. No voice recording or chat submission was triggered during setup.

## User acceptance completed

The user confirmed that Control+Option+Left/Right switches agents and displays the large label without opening the agent app. The user enabled Accessibility; refreshing the action editor removed the permission button, verifying that AXIsProcessTrusted() returns true for the running build. Input Monitoring was already confirmed granted. Voice/New chat are configured but were not automatically invoked during this verification.

## Screenshot action catalog and stacks

177 portable checks pass with the nine screenshot presets and ordered subset stacks. Presets use the supplied shortcuts: dot (Command+Period), new chat (Command+N), temporary chat (Shift+Command+N), standalone chat (Option+Command+O), side chat (Option+Command+S), voice start (Control+Command+V), voice end (Shift+Command+V), microphone (Control+Option+V), audio (Option+Shift+V). New catalog entries are unchecked. Existing checked New chat and Voice steps are preserved.

The native editor showed all nine actions with per-row inclusion checkboxes and reorder controls. Actual execution of all new presets remains a user acceptance check; voice availability and chat mode can affect which native app shortcuts apply.

## Configuration navigation preview

- Added a single Configuration entry point with Agents & actions, Headset buttons, Advanced settings, and Input diagnostics. The launcher remains for agent selection and immediate actions.
- Setup screens show their location and a back button. Only the current setup screen stays visible. Action configuration returns to Agents & actions; other setup screens return to Configuration.
- Advanced settings now shows shortcuts, activation timing, and compatibility without duplicating app selection and physical button setup.
- Native preview checks covered Configuration, Agents, action configuration, Headset buttons, Advanced settings, and the Launcher. Cancel preserved an edited compatibility checkbox; Discard returned to Configuration without saving it.
- The action labels are vertically centered using table-cell constraints. The native preview was visually inspected.
- The final arm64 build and signature verification passed, as did all 177 portable regression checks. Preview mode does not register global shortcuts or start headset input.
- Changes are in the source and `output/navigation-preview/Headset Remap Preview.app`. The working `build/Headset Remap.app` and its granted permissions were preserved. The revised navigation has not replaced that working build.

### Wider sections and collapsed advanced controls

- Configuration is 780 px wide, advanced settings 800 px, agent/button configuration 900 px, and action configuration 920 px. Section headings and horizontal separators distinguish the normal setup groups.
- Advanced/troubleshooting destinations, custom agent targets, switching shortcuts, action timing/global shortcuts, button conditions, and raw diagnostics are collapsed initially. Necessary validation errors remain visible.
- Native inspection confirmed the closed Configuration hub and Advanced settings state, expanding the hub, and the action editor with advanced options closed. The final arm64 preview builds and verifies its signature. It enters preview mode even when opened without command-line arguments, so reopening it does not start headset input or register competing global shortcuts.

## Evolve2 65 / Link 380 coexistence

- User identified the additional headset as Evolve2 65 with Link 380. IOKit reported both Link 380 (`0x24C8`) and Link 390 (`0x2E57`) attached over USB.
- Passive capture with mapped actions paused recorded repeated physical Evolve2 Teams-button inputs, including the user's short/long-press exercise. Link 380 emits `9B 01 00` followed by `9B 00 00`, decoded as page `0xFF99`, usage `4`, report `155`, element `76`, values `1`/`0`. Both adapters acknowledged the existing idle-client handshake with Microsoft Teams closed.
- Added backwards-compatible storage of multiple USB-product inputs per button. Learning replaces only the same product's binding; removal preserves remaining products. Button routing keeps independent held-key/debounce state per product. Duplicate mappings across physical button slots are rejected using signal identity, independent of the displayed device name.
- The button editor lists saved headset/adapter inputs and offers Learn another headset and removal of one selected input. All 197 portable checks passed, including replay of the observed Link 380 input, old settings migration, dual-device persistence, conflicts, relearning and deletion. Final installed-build acceptance is recorded below after the live test.

### Headset selection and microphone arm

- Added a detected-device selector to the launcher and menu-bar panel. It identifies USB adapters by product plus location, persists a specific selection, allows all connected devices, and blocks input from non-selected devices. Selection does not switch the OS audio device. Missing selected devices do not cause fallback to another device.
- Added an unassigned Microphone arm slot. The idle Evolve2 arm-only capture did not establish a reliable separate mute transition; no ambiguous input was assigned automatically. Duplicate binding validation prevents assigning an indistinguishable input to both the arm and mute slots.
- The test suite now passes 204 checks, covering independent device identity/filtering and stored selection in addition to the dual-input regressions.

### Installed build and hardware acceptance

- The full universal arm64/x86_64 build was installed at `build/Headset Remap.app`; signature verification passed. This deployment includes the previously previewed navigation changes. A copy of the prior app and its preferences was retained locally before rebuilding.
- The captured Link 380 Teams input was added to all six existing agent profiles while retaining their Link 390 input and action settings.
- The installed launcher detected Link 380, and selecting it persisted `9416:18030848` as the active button-input device. Input Monitoring was granted, and the adapter acknowledged the standalone handshake after restart.
- At 11:36:44, the live log recorded a Link 380 Teams-button match, successful Codex activation, successful Voice Chat action, and completion of the automatic action chain. The user confirmed that Codex opened with Voice Chat.
- Final checks: 204 portable mapping/profile/device-selection checks, 5 native Carbon registration/dispatch checks, and 5 voice-control label checks passed. Microphone-arm remapping remains unassigned because the idle capture did not establish a dependable arm-specific signal.

## Installed fixes and compact launcher row

The normal app bundle was replaced with the verified universal build containing the cancellation, audio-device scoping, physical-adapter debounce and attribution fixes. Binary hashes matched the tested build. Input Monitoring was granted and the Link 380 handshake completed. The native action editor no longer showed its keyboard-permission request after the separate Accessibility grant was renewed. Saved profiles and the selected Link 380 were unchanged; Codex remained selected with Voice Chat as its secondary action. No action shortcuts were fired during installation verification.

The subsequent launcher layout change places the existing configuration gear immediately beside a two-thirds-width headset dropdown and removes the bottom gear. A separate, clearly titled native preview (with headset listening and global shortcuts disabled) verified alignment and gear navigation. This later layout change is source/preview verified and is not yet installed in the running normal app, to avoid another permission reset during the active call.

The unchanged About handler was also exercised in the isolated preview: the native panel displayed Saif Hassan, Bård Ove Myhr, OpenAI Codex and AGPL v3. Clicking its README link opened `https://github.com/baardove/headset-remap/blob/main/README.md`. The normal app's right-click menu entry was source-verified; the About panel was not opened through that menu on the running normal app. The preview was stopped after testing. Only the normal remapper remained running, with the saved profiles and selected adapter unchanged.
