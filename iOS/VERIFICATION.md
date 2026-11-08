# iOS probe verification — 7 November 2026

## Completed

- Xcode 27.2 / iPhoneOS 27.2 SDK: unsigned generic iPhone build succeeded, app version 0.1.0, minimum iOS 17.
- iPhone 17 simulator / iOS 26.5: seven evidence unit tests passed. They cover read/notification separation, trial boundaries, overlapping trials, interrupted trials, log retention, report context/limitations, and generated PCM audio.
- Simulator UI test passed: launched app, started audible media playback, completed a 12-second idle trial with zero candidate events, opened the diagnostic report, verified its limitations and share control, stopped all tests, and verified the start-playback control returned.
- An initial UI-test failure came from looking for a lazily rendered control after scrolling it off screen. The test now scrolls to the control before asserting it; the corrected run passed.
- Inspected the simulator's rendered diagnostic report. The report separates observations from compatibility conclusions.
- No compiler warnings remain in the final device build apart from Xcode's harmless App Intents metadata message (this app has no App Intents).

Local test records (ignored build output):

- Unit tests: `build/simulator/Logs/Test/Test-JabraButtonProbe-2026.11.07_17-57-41-+0000.xcresult` (unit tests passed; the original UI test had the scrolling failure described above).
- Corrected UI test: `build/simulator/Logs/Test/Test-JabraButtonProbe-2026.11.07_17-58-47-+0000.xcresult`.
- Final unsigned iPhone app: `build/device/Build/Products/Debug-iphoneos/JabraButtonProbe.app`.

## Not yet verified

No real headset/button compatibility is claimed. BLE service access, notification delivery, actual media-button delivery, Bluetooth audio routing and locked-screen behavior need physical iPhone/headset trials.

Attempted development signing with the existing local certificate. Xcode reported **No Accounts** and no development profile for `local.jabrateamsremap.iosprobe`; no signed app was installed. Add the Apple Account in Xcode Settings → Accounts, select its team on the app target, and run on the phone. A separately started phone-destination build was canceled after device preparation stalled; the generic unsigned build completed successfully.

Follow-up after account sign-in: Xcode recognized the account, but provisioning failed with **PLA Update available**. Apple requires the account holder to accept the latest Program License Agreement before this team can create the development profile. The signed app has not yet been built or installed.

## Physical iPhone installation completed

After the user accepted the updated agreement and Apple's account state propagated, the development-signed build succeeded. `codesign --verify --deep --strict` passed for version 0.1.0. Once the user unlocked the iPhone with its passcode, `devicectl` confirmed installation and successful launch of `local.jabrateamsremap.iosprobe` on the iPhone 15 Pro Max. The earlier account, agreement and locked-device blockers above are resolved.

Signed build: `build/signed/Build/Products/Debug-iphoneos/JabraButtonProbe.app`.

Installation and launch do not establish headset compatibility. Physical button trials remain outstanding.
