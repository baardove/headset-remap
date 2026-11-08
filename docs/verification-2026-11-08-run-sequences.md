# Full configured Run sequences — 8 November 2026

Launcher Play, the menu-bar Run button/menu, and profile Run shortcuts now share the same entry point: run the primary action, then the profile's selected secondary action or checked action sequence. `None` still means primary only. Individual named-action shortcuts remain individual actions. Per the user's clarification, profile-selection shortcuts still only select an agent; cycle shortcuts also remain selection-only.

The sequence stops on primary or secondary failure and on configuration changes. Repeated Run triggers for the same profile are ignored while its sequence is running. Direct Run does not switch the selected headset profile. The launcher tooltip and detail text show the configured chain, and the popover button is labeled **Run … now**.

Validation:

- Full-source Swift typecheck and universal build passed; the running bundle's signature verified.
- Seven delayed-action cancellation checks, eighteen UI-button/persistence checks, and six Run-sequence ordering/failure/cancellation checks passed.
- Five in-process Carbon hotkey registration/dispatch checks passed without firing any agent actions.
- Clicked Grok's Play button in the rebuilt launcher. The live log recorded `RUN sequence started: Grok Bot`, `AGENT ACTION started: Grok Bot · Voice Chat`, and both completions at 13:58:03–13:58:04. An existing voice session was active, so the idempotent Grok action did not intentionally start another call.
- Automated key injection did not produce a new Carbon hotkey event in this session. Physical keyboard acceptance is therefore not claimed. The Run hotkey callback calls the same `runProfile` function as the verified Play button; selection callbacks retain their original `selectProfile` route.
