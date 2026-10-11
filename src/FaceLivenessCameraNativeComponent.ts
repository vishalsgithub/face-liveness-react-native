import {
  codegenNativeComponent,
  type CodegenTypes,
  type ViewProps,
} from 'react-native';

export type NativeLivenessResultEvent = Readonly<{
  hasFace: boolean;
  isLive: boolean;
  livenessScore: CodegenTypes.Float;
  detectionConfidence: CodegenTypes.Float;
  /** Face rectangle in view coordinates (points / dp). */
  frameX: CodegenTypes.Float;
  frameY: CodegenTypes.Float;
  frameWidth: CodegenTypes.Float;
  frameHeight: CodegenTypes.Float;
  /** Face rectangle in pixels of the upright camera frame. */
  boundsX: CodegenTypes.Float;
  boundsY: CodegenTypes.Float;
  boundsWidth: CodegenTypes.Float;
  boundsHeight: CodegenTypes.Float;
  imageWidth: CodegenTypes.Int32;
  imageHeight: CodegenTypes.Int32;
  processingTimeMs: CodegenTypes.Float;
  consecutiveLiveFrames: CodegenTypes.Int32;
  isVerified: boolean;
}>;

export type NativeCameraErrorEvent = Readonly<{
  code: string;
  message: string;
}>;

interface NativeProps extends ViewProps {
  active?: CodegenTypes.WithDefault<boolean, true>;
  livenessThreshold?: CodegenTypes.WithDefault<CodegenTypes.Float, 0.915>;
  requiredLiveFrames?: CodegenTypes.WithDefault<CodegenTypes.Int32, 8>;
  cameraPosition?: CodegenTypes.WithDefault<'front' | 'back', 'front'>;
  showFaceOverlay?: CodegenTypes.WithDefault<boolean, true>;
  onLivenessResult?: CodegenTypes.DirectEventHandler<NativeLivenessResultEvent>;
  onVerified?: CodegenTypes.DirectEventHandler<NativeLivenessResultEvent>;
  onCameraError?: CodegenTypes.DirectEventHandler<NativeCameraErrorEvent>;
}

export default codegenNativeComponent<NativeProps>('FaceLivenessCameraView');
