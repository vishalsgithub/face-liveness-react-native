//
//  FASLivenessCameraView.h
//  FaceAntiSpoofing
//
//  Drop-in camera preview that runs face detection + liveness on every frame.
//

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

#import "FASEngine.h"

NS_ASSUME_NONNULL_BEGIN

@class FASLivenessCameraView;

/// Result for one processed camera frame.
@interface FASLivenessResult : NSObject

/// Largest face in the frame, nil when no face was found.
@property (nonatomic, readonly, nullable) FASFace *face;
/// Face rectangle in the camera view's coordinate space, `CGRectNull` when no face.
@property (nonatomic, readonly) CGRect faceFrameInView;
/// Size of the (upright) camera frame that was analysed.
@property (nonatomic, readonly) CGSize imageSize;
/// Inference time in seconds.
@property (nonatomic, readonly) NSTimeInterval processingTime;

- (instancetype)init NS_UNAVAILABLE;

@end

@protocol FASLivenessCameraViewDelegate <NSObject>
@optional
/// Called on the main thread for every processed frame.
- (void)livenessCameraView:(FASLivenessCameraView *)view didProduceResult:(FASLivenessResult *)result;
/// Called on the main thread when the camera or the engine can't be started.
- (void)livenessCameraView:(FASLivenessCameraView *)view didFailWithError:(NSError *)error;
@end

@interface FASLivenessCameraView : UIView

/// Engine used for inference. Created with the bundled models on first `start` if nil.
@property (nonatomic, strong, nullable) FASEngine *engine;

@property (nonatomic, weak, nullable) IBOutlet id<FASLivenessCameraViewDelegate> delegate;

/// Block alternative to the delegate, called on the main thread.
@property (nonatomic, copy, nullable) void (^resultHandler)(FASLivenessResult *result);

/// Camera to use. Default `AVCaptureDevicePositionFront`. Changes apply on the next `start`.
@property (nonatomic) AVCaptureDevicePosition cameraPosition;

/// Draws a rectangle around the detected face. Default YES.
@property (nonatomic) IBInspectable BOOL showsFaceOverlay;
/// Overlay color for live faces. Default green.
@property (nonatomic, strong) IBInspectable UIColor *liveColor;
/// Overlay color for spoof faces. Default red.
@property (nonatomic, strong) IBInspectable UIColor *spoofColor;

@property (nonatomic, readonly, getter=isRunning) BOOL running;

/// Requests camera permission if needed, then starts the preview and analysis.
- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
