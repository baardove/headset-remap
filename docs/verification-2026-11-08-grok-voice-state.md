# Grok voice state and Stop — 8 November 2026

Grok's accessible **Hang up** control now establishes an active voice session. The monitor checks background windows once per second. A complete inspected composer with no Hang up establishes inactivity; an incomplete tree remains unknown. Active Codex or Grok voice changes the tray icon. Profiles configured with that agent's Voice action show **Voice active** and a square Stop button in the launcher. Explicit Stop rechecks state and never falls back to starting voice.

A headset or Run trigger while Grok voice is active skips the primary and subsequent actions, brings Grok forward, raises its focused window, clicks its currently located Hang up button, and confirms the inactive composer. Repeated triggers are suppressed during stopping. A covered-button result can retry for up to two seconds only when no click was sent. Once clicked, only state confirmation is retried, preventing an accidental second click from starting another session.

Validation:

- Full-source typecheck passed. Action tests passed 7 cancellation, 18 UI-button/persistence, 6 Run-sequence, and 10 Grok state/scope checks. Voice tests passed 5 label and 10 state/icon/polling checks.
- Universal build and strict code-signature verification passed. The updated app was launched from `build/Headset Remap.app`; Input Monitoring remained granted and Link 390 connected.
- Before the focus-readiness fix, physical Teams input at 14:02:16 was rejected by the hit-target check; a second physical press at 14:02:31 stopped the session, with inactivity confirmed at 14:02:32. The user confirmed it had stopped.
- The updated app launched at 14:04:07 and detected the user's active Grok session. Native UI inspection and screenshot confirmed **Voice active** and the square **Stop Grok Bot voice** control while other profiles retained Play.
- Final first-press acceptance passed: a single physical Teams input at 14:04:41.367 stopped Grok at 14:04:41.956, with inactivity confirmed at 14:04:41.974. The user confirmed **Stopped on the first press**. Native inspection showed Grok's Start voice chat control again and the launcher returned to Play with its configured action summary.

This supersedes the earlier pointer verification note's statement that an existing voice session is left running.
