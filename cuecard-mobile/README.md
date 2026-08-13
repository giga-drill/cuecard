# FloatCue iOS

FloatCue is the local-first iOS floating teleprompter built from the open-source CueCard mobile project. It keeps speaker notes visible in Picture in Picture while recording with Apple Camera.

## Bundle IDs

| Platform | Bundle ID |
|----------|-----------|
| FloatCue iOS | `com.gigadrill.floatcue` |
| Upstream Android | `com.thisisnsh.cuecard.android` |

## Firebase Setup

The iOS fork is local-first and no longer uses Firebase, Google Sign-In, Analytics, or Crashlytics. Its notes and settings remain on the device.

### Android Firebase Setup

1. Go to Firebase Console → Project Settings → Your Apps
2. Add an Android app with package name: `com.thisisnsh.cuecard.android`
3. Download `google-services.json`
4. Replace `android/app/google-services.json` with the downloaded file
5. Update Web Client ID in `LoginScreen.kt`:
   - Find your Web Client ID in Firebase Console → Authentication → Sign-in method → Google
   - Replace `YOUR_WEB_CLIENT_ID` in the code

## Prerequisites

### iOS Development
- macOS
- Xcode 15.0+
- iOS 17.0+ deployment target
- Apple Developer account (for device testing)

### Android Development
- Android Studio Hedgehog (2023.1.1) or newer
- JDK 17
- Android SDK 34
- Min SDK: 26 (Android 8.0)

## Building

### iOS

```bash
# Open in Xcode
open ios/FloatCue/FloatCue.xcodeproj

# Or build from command line
cd ios/FloatCue
xcodebuild -scheme FloatCue -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

The iOS fork currently includes portrait/landscape PiP, Mandarin on-device voice following, local script alignment, smooth voice-driven scrolling, and automatic fallback to fixed-speed scrolling. Apple Camera microphone coexistence still requires the manual real-device checklist in [`../docs/real-device-test-checklist.md`](../docs/real-device-test-checklist.md).

### Android

```bash
# Open in Android Studio
open -a "Android Studio" android/

# Or build from command line
cd android
./gradlew assembleDebug
```
