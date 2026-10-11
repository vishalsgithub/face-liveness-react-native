import { TurboModuleRegistry, type TurboModule } from 'react-native';

export type NativeFace = {
  x: number;
  y: number;
  width: number;
  height: number;
  detectionConfidence: number;
  livenessScore: number;
  isLive: boolean;
};

export interface Spec extends TurboModule {
  /** Detects faces in an image file (path or file:// URI). Largest face first. */
  detectInFile(
    path: string,
    livenessThreshold: number,
    allFaces: boolean
  ): Promise<NativeFace[]>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('FaceLiveness');
