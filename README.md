# @solankivishal/react-native-face-liveness

[![npm](https://img.shields.io/npm/v/@solankivishal/react-native-face-liveness.svg)](https://www.npmjs.com/package/@solankivishal/react-native-face-liveness)

On-device **face liveness (anti-spoofing) detection** for React Native. It checks whether the face in front of the camera is real or a presentation attack (printed photo, screen replay, mask) from ordinary camera frames. The user doesn't have to blink or turn their head, and nothing leaves the device.

- iOS and Android, built for the New Architecture (Fabric + TurboModules, JSI)
- `<FaceLivenessCamera />`: a ready-made camera component with a live verdict
- `FaceLiveness.detectInFile()`: checks photos
- No camera library or Babel/worklets setup needed
- Models are included (about 5.5 MB)

## Installation

```sh
npm install @solankivishal/react-native-face-liveness
# or
yarn add @solankivishal/react-native-face-liveness
```

```sh
cd ios && pod install
```

**iOS:** add the camera permission text to `ios/<YourApp>/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>The camera is used to check that a real person is in front of the device.</string>
```

**Android:** nothing to add. The camera permission is declared by the library and requested at runtime by `<FaceLivenessCamera />`. The first Android build downloads the prebuilt ncnn engine (about 21 MB) into `~/.face_liveness`; set `FACE_LIVENESS_NCNN_DIR` to use another folder.

**Expo:** works in a development build (`npx expo prebuild`), not in Expo Go. Add the camera text under `ios.infoPlist.NSCameraUsageDescription` in `app.json`.

Requirements: React Native 0.80+ with the New Architecture, iOS 15.1+, Android API 24+.

## Usage

### Camera component

```tsx
import { FaceLivenessCamera } from '@solankivishal/react-native-face-liveness';

<FaceLivenessCamera
  style={{ flex: 1 }}
  onVerified={(result) => {
    // A real face was seen for 8 consecutive frames.
    console.log('Real face', result.face?.livenessScore);
  }}
  onResult={(result) => {
    // Every processed frame: result.face is null when no face is visible.
  }}
  onError={(error) => console.warn(error.code, error.message)}
/>
```

| Prop | Default | Meaning |
| --- | --- | --- |
| `livenessThreshold` | `0.915` | Minimum score for a face to count as live |
| `requiredLiveFrames` | `8` | Consecutive live frames before `onVerified` is called |
| `cameraPosition` | `'front'` | `'front'` or `'back'` |
| `showFaceOverlay` | `true` | Draw a green or red box around the face |
| `active` | `true` | Set to `false` to pause the camera without unmounting |

Each `LivenessResult` contains:
- `face`: `{ bounds, frameInView, livenessScore, detectionConfidence, isLive }`, or `null` when no face is visible. `bounds` is in pixels of the upright frame; `frameInView` is in view coordinates.
- `isVerified`, `consecutiveLiveFrames`, `imageSize` and `processingTimeMs`.

`onError` codes are `permission-denied`, `camera-unavailable` and `engine-error`.

The camera pauses automatically when the app goes to the background.

### Photos

```ts
import { FaceLiveness } from '@solankivishal/react-native-face-liveness';

const faces = await FaceLiveness.detectInFile(photoUri); // path, file:// or content:// URI
if (faces.length > 0) {
  const face = faces[0]; // largest face
  console.log(face.isLive, face.livenessScore, face.bounds);
}
```

The photo's EXIF orientation is applied. Options: `{ livenessThreshold, allFaces }`.

A single frame is noisy. For a verification flow, rely on `onVerified`, which requires several consecutive live frames.

## How it works

1. **Face detection**: an SSD-style detector finds faces in a 192 px version of the frame.
2. **Liveness**: two MiniFASNet models look at the face at 2.7× and 4.0× context (resized to 80×80). Each outputs a "real face" probability, and the two are averaged.

A shared C++ engine runs both models on [ncnn](https://github.com/Tencent/ncnn). Camera frames are analysed natively on a background thread, and only the results cross into JavaScript.

## Example app

```sh
yarn
yarn example ios      # or: yarn example android
```

## Related packages

- Flutter: [face_liveness](https://pub.dev/packages/face_liveness)
- iOS (Swift Package Manager): [vishalsgithub/face-liveness](https://github.com/vishalsgithub/face-liveness)

## License

Apache-2.0. See [LICENSE](LICENSE). ncnn is distributed under BSD-3-Clause.
