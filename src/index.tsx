import { useCallback, useEffect, useState } from 'react';
import {
  PermissionsAndroid,
  Platform,
  type NativeSyntheticEvent,
  type ViewProps,
} from 'react-native';

import NativeFaceLivenessCamera, {
  type NativeCameraErrorEvent,
  type NativeLivenessResultEvent,
} from './FaceLivenessCameraNativeComponent';
import NativeFaceLiveness from './NativeFaceLiveness';

/** Default liveness threshold, same as the original Android sample. */
export const DEFAULT_LIVENESS_THRESHOLD = 0.915;

export type Rect = { x: number; y: number; width: number; height: number };

/** A detected face and its liveness result. */
export type LivenessFace = {
  /** Face bounds in pixels of the upright image. */
  bounds: Rect;
  /** Face detector confidence in [0, 1]. */
  detectionConfidence: number;
  /** Probability that the face is real (not a photo, screen or mask) in [0, 1]. */
  livenessScore: number;
  /** `livenessScore >= livenessThreshold`. */
  isLive: boolean;
};

/** Result of one processed camera frame. */
export type LivenessResult = {
  /** Largest face in the frame, or null when no face was found. */
  face: (LivenessFace & { frameInView: Rect }) | null;
  /** Size of the upright camera frame that `face.bounds` refers to. */
  imageSize: { width: number; height: number };
  /** Inference time for this frame in milliseconds. */
  processingTimeMs: number;
  /** Number of consecutive frames (including this one) with a live face. */
  consecutiveLiveFrames: number;
  /** True once a face has been live for `requiredLiveFrames` consecutive frames. */
  isVerified: boolean;
};

export type CameraError = { code: string; message: string };

export type FaceLivenessCameraProps = ViewProps & {
  /** Called for every processed frame. */
  onResult?: (result: LivenessResult) => void;
  /** Called once each time a face becomes verified. */
  onVerified?: (result: LivenessResult) => void;
  /** Called when the camera can't be started (e.g. permission denied). */
  onError?: (error: CameraError) => void;
  /** Pause the camera without unmounting. Default true. */
  active?: boolean;
  /** Default 0.915. Higher is stricter. */
  livenessThreshold?: number;
  /** Consecutive live frames before `onVerified`. Default 8. */
  requiredLiveFrames?: number;
  /** Default 'front'. */
  cameraPosition?: 'front' | 'back';
  /** Draw a green / red box around the face. Default true. */
  showFaceOverlay?: boolean;
};

function toResult(e: NativeLivenessResultEvent): LivenessResult {
  return {
    face: e.hasFace
      ? {
          bounds: {
            x: e.boundsX,
            y: e.boundsY,
            width: e.boundsWidth,
            height: e.boundsHeight,
          },
          frameInView: {
            x: e.frameX,
            y: e.frameY,
            width: e.frameWidth,
            height: e.frameHeight,
          },
          detectionConfidence: e.detectionConfidence,
          livenessScore: e.livenessScore,
          isLive: e.isLive,
        }
      : null,
    imageSize: { width: e.imageWidth, height: e.imageHeight },
    processingTimeMs: e.processingTimeMs,
    consecutiveLiveFrames: e.consecutiveLiveFrames,
    isVerified: e.isVerified,
  };
}

/**
 * Camera preview that checks every frame for a real face.
 *
 * ```tsx
 * <FaceLivenessCamera
 *   style={{ flex: 1 }}
 *   onVerified={(r) => console.log('Real face', r.face?.livenessScore)}
 * />
 * ```
 */
export function FaceLivenessCamera({
  onResult,
  onVerified,
  onError,
  active = true,
  livenessThreshold = DEFAULT_LIVENESS_THRESHOLD,
  requiredLiveFrames = 8,
  cameraPosition = 'front',
  showFaceOverlay = true,
  ...viewProps
}: FaceLivenessCameraProps) {
  // iOS asks for camera permission natively; Android needs a runtime request.
  const [permitted, setPermitted] = useState(Platform.OS !== 'android');

  useEffect(() => {
    if (Platform.OS !== 'android') return;
    let cancelled = false;
    PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.CAMERA).then(
      (status) => {
        if (cancelled) return;
        if (status === PermissionsAndroid.RESULTS.GRANTED) {
          setPermitted(true);
        } else {
          onError?.({
            code: 'permission-denied',
            message: 'Camera permission denied.',
          });
        }
      }
    );
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleResult = useCallback(
    (e: NativeSyntheticEvent<NativeLivenessResultEvent>) =>
      onResult?.(toResult(e.nativeEvent)),
    [onResult]
  );
  const handleVerified = useCallback(
    (e: NativeSyntheticEvent<NativeLivenessResultEvent>) =>
      onVerified?.(toResult(e.nativeEvent)),
    [onVerified]
  );
  const handleError = useCallback(
    (e: NativeSyntheticEvent<NativeCameraErrorEvent>) =>
      onError?.({ code: e.nativeEvent.code, message: e.nativeEvent.message }),
    [onError]
  );

  return (
    <NativeFaceLivenessCamera
      {...viewProps}
      active={active && permitted}
      livenessThreshold={livenessThreshold}
      requiredLiveFrames={requiredLiveFrames}
      cameraPosition={cameraPosition}
      showFaceOverlay={showFaceOverlay}
      onLivenessResult={handleResult}
      onVerified={handleVerified}
      onCameraError={handleError}
    />
  );
}

/** Still-image detection. */
export const FaceLiveness = {
  /**
   * Detects faces in an image file (path or `file://` URI, JPEG/PNG/HEIC).
   * EXIF orientation is applied. Returns the largest face first.
   */
  async detectInFile(
    path: string,
    options: { livenessThreshold?: number; allFaces?: boolean } = {}
  ): Promise<LivenessFace[]> {
    const faces = await NativeFaceLiveness.detectInFile(
      path,
      options.livenessThreshold ?? DEFAULT_LIVENESS_THRESHOLD,
      options.allFaces ?? false
    );
    return faces.map((f) => ({
      bounds: { x: f.x, y: f.y, width: f.width, height: f.height },
      detectionConfidence: f.detectionConfidence,
      livenessScore: f.livenessScore,
      isLive: f.isLive,
    }));
  },
};
