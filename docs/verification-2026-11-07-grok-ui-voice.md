# Grok Bot UI voice action — 7 November 2026

Historical first implementation. The `AXPress` behavior below was superseded by the [verified pointer-click integration on 8 November](verification-2026-11-08-grok-pointer-voice.md).

Implemented the `uiButton` secondary-action kind and a Grok Voice preset targeting the exact accessible label **Start voice chat**. The separate **Start voice input** control is not selected by this preset. The primary action opens Grok; the secondary action waits 0.6 seconds and performs `AXPress` on one enabled matching button in the focused window. Missing/ambiguous controls, incomplete inspection, changed labels, canceled configuration and app focus changes are handled as errors rather than coordinate-click fallbacks.

## Validation

- Full-source Swift typecheck passed.
- Universal Apple Silicon / Intel build and signature verification passed.
- 214 existing mapping/profile/button/audio-rule checks passed.
- Seven delayed-action cancellation checks and twelve button matching/persistence checks passed, without launching apps or pressing live buttons.
- Read-only lookup through the rebuilt app found one enabled **Start voice chat** button in `com.anysphere.sand`; that control exposes `AXPress`.
- Current Grok profile was configured to select the new Voice Chat secondary action. Other profiles and the active profile identity were verified unchanged by the configuration helper.
- Native launcher inspection shows **Open Grok Bot → Voice Chat**, Grok selected, and **Using Jabra Link 380**.
- Rebuilding invalidated the previous Input Monitoring grant. After macOS authentication, toggling the old entry alone did not restore it. A reset limited to `ListenEvent` for `local.jabrateamsremap`, followed by adding the rebuilt app and restarting it, restored the launcher's ready state. Other apps' grants were left untouched.

The previous app and preferences are backed up under ignored `output/grok-ui-preview/`. This action has not yet been triggered against a live Grok voice session; physical headset-to-voice acceptance remains for the user to test. It starts voice chat only and does not implement a Grok stop/toggle action.
