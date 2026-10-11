#import "FaceLivenessCameraComponentView.h"

#import <react/renderer/components/FaceLivenessSpec/ComponentDescriptors.h>
#import <react/renderer/components/FaceLivenessSpec/EventEmitters.h>
#import <react/renderer/components/FaceLivenessSpec/Props.h>
#import <react/renderer/components/FaceLivenessSpec/RCTComponentViewHelpers.h>

#import "RCTFabricComponentsPlugins.h"

#import "FASLivenessCameraView.h"

using namespace facebook::react;

@interface FaceLivenessCameraComponentView () <FASLivenessCameraViewDelegate>
@end

@implementation FaceLivenessCameraComponentView {
    FASLivenessCameraView *_camera;
    BOOL _active;
    float _threshold;
    int _requiredLiveFrames;
    int _consecutiveLive;
    BOOL _verifiedNotified;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
    return concreteComponentDescriptorProvider<FaceLivenessCameraViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        static const auto defaultProps = std::make_shared<const FaceLivenessCameraViewProps>();
        _props = defaultProps;

        _active = YES;
        _threshold = FASEngine.defaultLivenessThreshold;
        _requiredLiveFrames = 8;

        _camera = [[FASLivenessCameraView alloc] initWithFrame:frame];
        _camera.delegate = self;
        __weak __typeof(self) weakSelf = self;
        _camera.resultHandler = ^(FASLivenessResult *result) {
            [weakSelf handleResult:result];
        };
        self.contentView = _camera;
    }
    return self;
}

- (void)updateProps:(Props::Shared const &)props oldProps:(Props::Shared const &)oldProps
{
    const auto &oldViewProps = *std::static_pointer_cast<FaceLivenessCameraViewProps const>(_props);
    const auto &newViewProps = *std::static_pointer_cast<FaceLivenessCameraViewProps const>(props);

    _threshold = newViewProps.livenessThreshold;
    _camera.engine.livenessThreshold = _threshold;
    _requiredLiveFrames = MAX(1, newViewProps.requiredLiveFrames);
    _camera.showsFaceOverlay = newViewProps.showFaceOverlay;

    AVCaptureDevicePosition position = newViewProps.cameraPosition == FaceLivenessCameraViewCameraPosition::Back
                                           ? AVCaptureDevicePositionBack
                                           : AVCaptureDevicePositionFront;
    BOOL positionChanged = _camera.cameraPosition != position;
    _camera.cameraPosition = position;

    BOOL activeChanged = oldViewProps.active != newViewProps.active || _active != newViewProps.active;
    _active = newViewProps.active;

    [super updateProps:props oldProps:oldProps];

    if (positionChanged && _camera.isRunning) {
        [_camera stop];
        [self resetVerification];
    }
    if (activeChanged || positionChanged) [self updateRunning];
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    [self updateRunning];
}

- (void)prepareForRecycle
{
    [super prepareForRecycle];
    [_camera stop];
    [self resetVerification];
}

- (void)updateRunning
{
    const BOOL shouldRun = _active && self.window != nil;
    if (shouldRun && !_camera.isRunning) {
        [_camera start];
    } else if (!shouldRun && _camera.isRunning) {
        [_camera stop];
        [self resetVerification];
    }
}

- (void)resetVerification
{
    _consecutiveLive = 0;
    _verifiedNotified = NO;
}

#pragma mark - Results

- (void)handleResult:(FASLivenessResult *)result
{
    // The engine is created lazily by the camera view; keep its threshold in sync.
    _camera.engine.livenessThreshold = _threshold;

    FASFace *face = result.face;
    const BOOL live = face != nil && face.livenessScore >= _threshold;
    if (live) {
        _consecutiveLive++;
    } else {
        _consecutiveLive = 0;
        _verifiedNotified = NO;
    }
    const BOOL verified = _consecutiveLive >= _requiredLiveFrames;

    auto emitter = std::static_pointer_cast<const FaceLivenessCameraViewEventEmitter>(_eventEmitter);
    if (!emitter) return;

    FaceLivenessCameraViewEventEmitter::OnLivenessResult event{};
    event.hasFace = face != nil;
    event.isLive = live;
    event.livenessScore = face ? face.livenessScore : 0;
    event.detectionConfidence = face ? face.detectionConfidence : 0;
    if (face) {
        event.frameX = result.faceFrameInView.origin.x;
        event.frameY = result.faceFrameInView.origin.y;
        event.frameWidth = result.faceFrameInView.size.width;
        event.frameHeight = result.faceFrameInView.size.height;
        event.boundsX = face.bounds.origin.x;
        event.boundsY = face.bounds.origin.y;
        event.boundsWidth = face.bounds.size.width;
        event.boundsHeight = face.bounds.size.height;
    }
    event.imageWidth = (int)result.imageSize.width;
    event.imageHeight = (int)result.imageSize.height;
    event.processingTimeMs = result.processingTime * 1000.0;
    event.consecutiveLiveFrames = _consecutiveLive;
    event.isVerified = verified;
    emitter->onLivenessResult(event);

    if (verified && !_verifiedNotified) {
        _verifiedNotified = YES;
        FaceLivenessCameraViewEventEmitter::OnVerified verifiedEvent{};
        verifiedEvent.hasFace = event.hasFace;
        verifiedEvent.isLive = event.isLive;
        verifiedEvent.livenessScore = event.livenessScore;
        verifiedEvent.detectionConfidence = event.detectionConfidence;
        verifiedEvent.frameX = event.frameX;
        verifiedEvent.frameY = event.frameY;
        verifiedEvent.frameWidth = event.frameWidth;
        verifiedEvent.frameHeight = event.frameHeight;
        verifiedEvent.boundsX = event.boundsX;
        verifiedEvent.boundsY = event.boundsY;
        verifiedEvent.boundsWidth = event.boundsWidth;
        verifiedEvent.boundsHeight = event.boundsHeight;
        verifiedEvent.imageWidth = event.imageWidth;
        verifiedEvent.imageHeight = event.imageHeight;
        verifiedEvent.processingTimeMs = event.processingTimeMs;
        verifiedEvent.consecutiveLiveFrames = event.consecutiveLiveFrames;
        verifiedEvent.isVerified = YES;
        emitter->onVerified(verifiedEvent);
    }
}

#pragma mark - FASLivenessCameraViewDelegate

- (void)livenessCameraView:(FASLivenessCameraView *)view didFailWithError:(NSError *)error
{
    auto emitter = std::static_pointer_cast<const FaceLivenessCameraViewEventEmitter>(_eventEmitter);
    if (!emitter) return;
    NSString *code;
    switch (error.code) {
        case FASErrorCameraPermissionDenied: code = @"permission-denied"; break;
        case FASErrorCameraUnavailable: code = @"camera-unavailable"; break;
        default: code = @"engine-error"; break;
    }
    FaceLivenessCameraViewEventEmitter::OnCameraError event{};
    event.code = std::string(code.UTF8String);
    event.message = std::string(error.localizedDescription.UTF8String ?: "");
    emitter->onCameraError(event);
}

@end

Class<RCTComponentViewProtocol> FaceLivenessCameraViewCls(void)
{
    return FaceLivenessCameraComponentView.class;
}
