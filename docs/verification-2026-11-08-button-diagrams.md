# Headset button diagrams and model-specific availability

Headset buttons now includes the exact overview illustrations for 16 models: Evolve2 30, 30 SE, 40, 40 SE, 50, 55, 65, 65 Flex, 75, 85 and Buds; Evolve3 45, 65, 65 Flex, 75 and 85. Source URLs and overview page numbers are recorded in `assets/HeadsetDiagrams/sources.json`. Only the current model's drawing is shown. Numbers follow left-side controls from top to bottom, then right-side controls from top to bottom; shared functions retain one number. The Evolve2 65 power/Bluetooth slider is last on its right side, as corrected by the user.

Button debug has independent availability settings for every model. Unchecking a button hides it from that model's configuration list and excludes its mapped actions from incoming HID dispatch. Saved profile settings and learned inputs are preserved. Input learning and the headset's native functions remain available. This does not assert that every illustrated control can be remapped.

Factory product names identify exact models when exposed by the selected input device. Otherwise model tabs are shown, with explicit choices saved per adapter. As requested for this setup, Link 380 selects the Evolve2 series and Link 390 selects the Evolve3 series; this fallback is distinct from confirmed exact-model detection. All models fit in one tab row on the main page; narrower windows wrap as needed.

Validation:

- Full-source typecheck passed.
- All 252 mapping/profile/audio checks passed, including availability, model isolation, exact-name detection, manual choices, adapter defaults, numbering, disabled dispatch and restoration without losing bindings.
- Inspected both diagrams and the selected-button highlight in the running app. Selecting Microphone arm showed the model-specific explanation that Evolve3 has no boom arm.
- Native UI test unchecked Evolve3 Microphone arm and verified Evolve2 Microphone arm stayed checked. The Evolve3 choice persisted when switching models.
- The earlier temporary Evolve3 microphone-arm exclusion was restored. No test exclusions are left enabled.
- Final native UI check: all 11 Evolve2 model tabs fit on one row in the main configuration page; the narrower debug window wraps them. Only the current model's diagram is displayed, with visible numbered callouts and matching list numbers.
- Selecting Link 380 in the launcher selected Evolve2 mode on the button page. Restored Link 390 and its Evolve3 75 choice afterward, without changing the selected Codex profile or ending its active voice session.
- Unchecked Evolve2 Power/Bluetooth in Button debug; Evolve3 Power/Bluetooth remained checked. Restored the Evolve2 checkbox before completion.

Exact-model detection is based on an exposed headset product name. Link-based series selection is a user-requested default, not automatic identification of whatever headset might later be paired to an adapter.
