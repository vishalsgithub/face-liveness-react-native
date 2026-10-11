//
//  FASEngine.h
//  FaceAntiSpoofing
//
//  On-device face detection + silent liveness (anti-spoofing) for iOS.
//

#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const FASErrorDomain;

typedef NS_ERROR_ENUM(FASErrorDomain, FASErrorCode) {
    FASErrorModelNotLoaded = -100,
    FASErrorInvalidImage = -101,
    FASErrorInvalidConfig = -102,
    FASErrorLoadDetector = -103,
    FASErrorLoadLiveness = -104,
    FASErrorModelsNotFound = -200,
    FASErrorUnsupportedPixelFormat = -201,
    FASErrorCameraPermissionDenied = -300,
    FASErrorCameraUnavailable = -301,
};

/// EXIF orientation describing how to turn the buffer into an upright image.
typedef NS_ENUM(NSInteger, FASImageOrientation) {
    FASImageOrientationUp = 1,
    FASImageOrientationUpMirrored = 2,
    FASImageOrientationDown = 3,
    FASImageOrientationDownMirrored = 4,
    FASImageOrientationLeftMirrored = 5,
    FASImageOrientationRight = 6,
    FASImageOrientationRightMirrored = 7,
    FASImageOrientationLeft = 8,
};

typedef NS_ENUM(NSInteger, FASPixelFormat) {
    FASPixelFormatRGBA,
    FASPixelFormatBGRA,
    FASPixelFormatRGB,
    FASPixelFormatBGR,
    /// Contiguous Y plane followed by interleaved VU.
    FASPixelFormatNV21,
    /// Contiguous Y plane followed by interleaved UV.
    FASPixelFormatNV12,
};

/// A detected face and its liveness result.
@interface FASFace : NSObject

/// Face bounds in pixels of the upright image.
@property (nonatomic, readonly) CGRect bounds;
/// Face detector confidence in [0, 1].
@property (nonatomic, readonly) float detectionConfidence;
/// Probability that the face is real (not a photo, screen or mask) in [0, 1].
@property (nonatomic, readonly) float livenessScore;
/// `livenessScore >= livenessThreshold` of the engine at detection time.
@property (nonatomic, readonly, getter=isLive) BOOL live;

- (instancetype)initWithBounds:(CGRect)bounds
           detectionConfidence:(float)detectionConfidence
                 livenessScore:(float)livenessScore
                          live:(BOOL)live NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

/// Face detection + liveness engine. All methods are thread-safe (calls are serialized).
@interface FASEngine : NSObject

/// Default liveness threshold (0.915), same as the Android sample.
@property (class, nonatomic, readonly) float defaultLivenessThreshold;

/// Bundle that contains the default models (the SwiftPM resource bundle, or `FaceAntiSpoofingModels.bundle` with CocoaPods).
@property (class, nonatomic, readonly, nullable) NSBundle *modelBundle;

/// Creates an engine with the bundled models (`try FASEngine.bundled()` in Swift).
+ (nullable instancetype)bundledEngineWithError:(NSError **)error NS_SWIFT_NAME(bundled());

/// Creates an engine from a directory containing `detection/` and `live/` (or a flat directory).
- (nullable instancetype)initWithModelDirectory:(NSString *)directory
                                          error:(NSError **)error NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// Faces with `livenessScore >= livenessThreshold` are reported as live. Default 0.915.
@property (atomic) float livenessThreshold;
/// Minimum face size in pixels (of the upright image). Default 64.
@property (atomic) NSInteger minFaceSize;
/// Minimum face detector confidence. Default 0.6.
@property (atomic) float faceDetectionThreshold;
/// Number of CPU threads used for inference. Default 2.
@property (atomic) NSInteger numThreads;
/// When NO (default) only the largest face is evaluated and returned.
@property (atomic) BOOL evaluatesAllFaces;

/// Detects faces in a camera frame. Supports 32BGRA and 420 bi-planar (NV12) pixel buffers.
- (nullable NSArray<FASFace *> *)detectFacesInPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                              orientation:(FASImageOrientation)orientation
                                                    error:(NSError **)error
    NS_SWIFT_NAME(detectFaces(in:orientation:));

/// Detects faces in a still image (its `imageOrientation` is honoured).
/// Returned bounds are in pixels of the upright image (`image.size * image.scale`).
- (nullable NSArray<FASFace *> *)detectFacesInImage:(UIImage *)image
                                              error:(NSError **)error
    NS_SWIFT_NAME(detectFaces(in:));

/// Detects faces in raw pixels (used by the Flutter / React Native bindings).
- (nullable NSArray<FASFace *> *)detectFacesInBytes:(const void *)bytes
                                              width:(NSInteger)width
                                             height:(NSInteger)height
                                        bytesPerRow:(NSInteger)bytesPerRow
                                        pixelFormat:(FASPixelFormat)pixelFormat
                                        orientation:(FASImageOrientation)orientation
                                              error:(NSError **)error
    NS_SWIFT_NAME(detectFaces(bytes:width:height:bytesPerRow:pixelFormat:orientation:));

@end

NS_ASSUME_NONNULL_END
