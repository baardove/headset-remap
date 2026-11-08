# Jabra Button Probe for iPhone

A small diagnostic app to find out whether an iPhone can observe a Jabra Teams-button press. This is a feasibility probe, not a remapper. It does not start an assistant, dictate, record the microphone, send data to a server, or run the Mac app's Teams handshake.

Requires iOS 17 or later and Xcode. The app uses only public iOS APIs. Physical iPhone and headset testing is required; the simulator cannot establish headset compatibility.

## Install on your iPhone

1. Open `JabraButtonProbe.xcodeproj` in Xcode.
2. Select the **JabraButtonProbe** app target → **Signing & Capabilities**, choose your development team, and change the bundle identifier if needed.
3. Connect and unlock the iPhone, select it as the run destination, enable Developer Mode if requested, and press Run. A free Apple development account can be used subject to Apple's provisioning limits.
4. Allow Bluetooth when you first scan. No microphone permission is requested.

The checked-in Xcode project works without XcodeGen. To regenerate it after changing `project.yml`, run `xcodegen generate` in this directory.

If Xcode reports **No Accounts** or **No profiles**, add your Apple Account under **Xcode → Settings → Accounts**, then select the team on the app target. A signing certificate on its own is not sufficient to provision a new iPhone app.

## Hardware test

1. Pair the headset in **iPhone Settings → Bluetooth**. Enter its model in the app. Initially disconnect its Link adapter / other paired computer to avoid routing the button there. Stay out of calls.
2. Tap **Scan Bluetooth LE**. Select your headset, not another nearby device. If missing, try pairing mode and scan again. The remembered device and standard Battery/Device Information/HID service hints may help find an already connected peripheral, but they are not an exhaustive lookup.
3. If it connects, wait for service discovery and notification subscriptions to settle. Run **Idle baseline** without touching anything. Run **Teams button** and press/release Teams three times, around two seconds apart. Run **Play/pause control** and do the same with play/pause. Each trial lasts 12 seconds. Repeat the sequence.
4. Separately, start **Optional media-button test**. This plays a quiet, audible tone and makes the app eligible to receive media commands. It may pause existing playback. Confirm the audio route says Jabra and you hear the tone in the headset; use iOS's audio output picker if necessary. Repeat the trials. Play/pause should be a useful positive control. Media pause really pauses the tone; resume it in the app before the next trial. The test stops after two minutes, on audio interruption/output disconnection, or when stopped manually.
5. Tap **Report**, review, then share/copy the report. Mark whether presses were short or long and repeat separately if trying both. Test foreground first. Locked-screen results can be collected separately during active media playback; do not assume an app without playback will remain runnable in the background.
6. Tap **Stop all tests** when done. This cancels scanning, the selected BLE connection/subscriptions, and test playback.

If the headset will not connect over BLE, skip that channel and still try the media test. A Classic Bluetooth audio pairing is distinct from a Core Bluetooth peripheral connection.

## What the evidence means

- **BLE notification:** raw values received from a selected peripheral's notify/indicate characteristics. Compare timestamps and bytes with repeated presses and the idle baseline. Battery/telemetry changes are not automatically button signals. Initial reads are labeled `read` and excluded from trial candidate counts.
- **Media command:** iOS delivered play/pause/next/etc. to this app. iOS does not tell the app which physical button/device sent it. Avoid Control Center or other remotes during trials. A working play/pause control with silent Teams presses is useful negative evidence for the media route.
- **ExternalAccessory:** lists accessory metadata and protocols visible to this app. No vendor protocols are guessed or declared, no accessory sessions are opened, and an empty list is inconclusive. Vendor access may require authorization and a declared protocol.
- **No events:** no usable event was observed through these tested APIs under these conditions. This does not prove all integrations are impossible. Raw Bluetooth Classic / USB HID reports are not exposed by this probe. Notification subscription failure is a channel failure, not proof that the button emits nothing.

All event history stays in memory, except the last selected BLE identifier in local preferences. Export is explicit. The bounded log retains 600 events and reports omitted events; trial totals are retained independently. Reports may contain nearby device names, UUIDs, advertised manufacturer data, accessory metadata and raw values. Review before sharing. The app issues GATT discovery/read and notification subscription requests, but no characteristic-value writes, vendor handshake, firmware updates or remapping commands.

## Build and tests

```sh
xcodebuild -project JabraButtonProbe.xcodeproj -scheme JabraButtonProbe \
  -destination 'generic/platform=iOS' -derivedDataPath build/device \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project JabraButtonProbe.xcodeproj -scheme JabraButtonProbe \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/simulator CODE_SIGNING_ALLOWED=NO test
```

Choose a simulator installed on your Mac (`xcrun simctl list devices available`). Unit tests verify evidence classification, trial boundaries, interruption, bounded log behavior, report limitations, and test-audio format. They do not validate Bluetooth, accessory visibility, media routing, Teams presses or background execution on hardware.

## API references

- [Jabra mobile SDK support](https://developer.jabra.com/sdks-and-tools/android-ios): Perform/BlueParrott only; no public Evolve-family mobile SDK listed.
- [Core Bluetooth peripheral discovery](https://developer.apple.com/documentation/corebluetooth/cbperipheral)
- [Connected-peripheral lookup](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/retrieveconnectedperipherals(withservices:))
- [Media remote commands](https://developer.apple.com/documentation/mediaplayer/remote-command-center-events)
- [External Accessory protocols](https://developer.apple.com/documentation/externalaccessory/eaaccessory/protocolstrings)

Part of Headset Remap; repository AGPL-3.0 license applies. See the root LICENSE and PROVENANCE.md.
