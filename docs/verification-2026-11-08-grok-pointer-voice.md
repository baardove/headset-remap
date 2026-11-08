# Grok voice click verification — 8 November 2026

The Link 390 was already selected and physical Teams presses reached the Grok action on 7 November. The previous implementation incorrectly treated a successful Accessibility `AXPress` return as confirmation that voice had opened. A regular UI click opened Grok's voice panel successfully.

The Grok integration now finds the exact **Start voice chat** button, reads its current bounds, verifies the hit target at its center, sends a pointer click, and waits for the **Hang up** control before reporting success. An existing voice panel is left running. Generic UI-button actions retain `AXPress`. Missing or covered controls, invalid bounds, loss of app focus, and canceled configuration prevent clicks; startup confirmation failure is reported rather than retried with a second click.

Validation:

- Full-source typecheck passed; universal build and code-signature verification passed.
- Seven delayed-action cancellation checks and eighteen UI-button/persistence/geometry checks passed without real input.
- Triggered **Test action** in the installed Headset Remap app. Observed Grok's voice panel with **Mute** and **Hang up**. The log recorded `AGENT ACTION completed: Voice Chat` at 13:33:33 local time. Ended the test call afterward.
- A subsequent physical Link 390 press at 13:33:35 was captured, but the user-selected active profile was **Codex**; it therefore launched Codex's voice action. This is not physical Grok end-to-end acceptance. Select Grok in the launcher to test that route.
- Refreshed only this app's Input Monitoring and app-control permissions after replacing its signing identity. The build script now prefers an unambiguous Apple Development certificate (after an explicit override or the original local certificate) to maintain a stable identity across future rebuilds.

The user also requested that the primary action summary and **Choose app…** button share one row. After a universal rebuild, visually verified **Opens Grok Bot** and **Choose app…** side by side in the running Agents window. Long labels truncate before the button is compressed. The rebuild reused the Apple Development signing identity; Input Monitoring stayed granted, and the launcher showed **Using Jabra Link 390** without another permission prompt.
