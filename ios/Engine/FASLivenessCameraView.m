//
//  FASLivenessCameraView.m
//  FaceAntiSpoofing
//

#import "FASLivenessCameraView.h"

#import <QuartzCore/QuartzCore.h>

@interface FASLivenessResult ()
- (instancetype)initWithFace:(nullable FASFace *)face
             faceFrameInView:(CGRect)faceFrameInView
                   imageSize:(CGSize)imageSize
              processingTime:(NSTimeInterval)processingTime;
@end

@implementation FASLivenessResult

- (instancetype)initWithFace:(FASFace *)face
             faceFrameInView:(CGRect)faceFrameInView
                   imageSize:(CGSize)imageSize
              processingTime:(NSTimeInterval)processingTime {
    if ((self = [super init])) {
        _face = face;
        _faceFrameInView = faceFrameInView;
        _imageSize = imageSize;
        _processingTime = processingTime;
    }
    return self;
}

@end

@interface FASLivenessCameraView () <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, readwrite, getter=isRunning) BOOL running;
@end

@implementation FASLivenessCameraView {
    AVCaptureSession *_session;
    AVCaptureVideoDataOutput *_videoOutput;
    dispatch_queue_t _sessionQueue;
    dispatch_queue_t _videoQueue;
    CAShapeLayer *_overlayLayer;
    // Accessed on the session queue.
    AVCaptureVideoOrientation _videoOrientation;
    BOOL _configured;
    AVCaptureDevicePosition _configuredPosition;
    // Engine snapshot used on the video queue.
    FASEngine *_activeEngine;
}

+ (Class)layerClass {
    return AVCaptureVideoPreviewLayer.class;
}

- (AVCaptureVideoPreviewLayer *)previewLayer {
    return (AVCaptureVideoPreviewLayer *)self.layer;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    _cameraPosition = AVCaptureDevicePositionFront;
    _showsFaceOverlay = YES;
    _liveColor = UIColor.systemGreenColor;
    _spoofColor = UIColor.systemRedColor;
    _videoOrientation = AVCaptureVideoOrientationPortrait;

    _session = [[AVCaptureSession alloc] init];
    _sessionQueue = dispatch_queue_create("com.faceantispoofing.camera.session", DISPATCH_QUEUE_SERIAL);
    _videoQueue = dispatch_queue_create("com.faceantispoofing.camera.video", DISPATCH_QUEUE_SERIAL);

    self.backgroundColor = UIColor.blackColor;
    self.previewLayer.session = _session;
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

    _overlayLayer = [CAShapeLayer layer];
    _overlayLayer.fillColor = UIColor.clearColor.CGColor;
    _overlayLayer.lineWidth = 3;
    _overlayLayer.hidden = YES;
    [self.layer addSublayer:_overlayLayer];
}

- (void)dealloc {
    AVCaptureSession *session = _session;
    dispatch_async(_sessionQueue, ^{
        if (session.isRunning) [session stopRunning];
    });
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _overlayLayer.frame = self.bounds;

    UIWindowScene *scene = self.window.windowScene;
    if (scene) {
        AVCaptureVideoOrientation orientation = [self videoOrientationForInterfaceOrientation:scene.interfaceOrientation];
        dispatch_async(_sessionQueue, ^{
            if (self->_videoOrientation != orientation) {
                self->_videoOrientation = orientation;
                [self applyVideoOrientation];
            }
        });
    }
}

#pragma mark - Public

- (void)start {
    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]) {
        case AVAuthorizationStatusAuthorized:
            [self startSession];
            break;
        case AVAuthorizationStatusNotDetermined: {
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                                     completionHandler:^(BOOL granted) {
                                         dispatch_async(dispatch_get_main_queue(), ^{
                                             if (granted) {
                                                 [self startSession];
                                             } else {
                                                 [self reportError:FASErrorCameraPermissionDenied
                                                           message:@"Camera permission denied."];
                                             }
                                         });
                                     }];
            break;
        }
        default:
            [self reportError:FASErrorCameraPermissionDenied message:@"Camera permission denied."];
            break;
    }
}

- (void)stop {
    self.running = NO;
    _overlayLayer.hidden = YES;
    AVCaptureSession *session = _session;
    dispatch_async(_sessionQueue, ^{
        if (session.isRunning) [session stopRunning];
    });
}

- (void)setShowsFaceOverlay:(BOOL)showsFaceOverlay {
    _showsFaceOverlay = showsFaceOverlay;
    if (!showsFaceOverlay) _overlayLayer.hidden = YES;
}

#pragma mark - Session

- (void)startSession {
    FASEngine *engine = self.engine;
    AVCaptureDevicePosition position = self.cameraPosition;
    self.running = YES;

    dispatch_async(_sessionQueue, ^{
        FASEngine *activeEngine = engine;
        if (!activeEngine) {
            NSError *error;
            activeEngine = [FASEngine bundledEngineWithError:&error];
            if (!activeEngine) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.running = NO;
                    [self reportError:error];
                });
                return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!self.engine) self.engine = activeEngine;
            });
        }
        dispatch_sync(self->_videoQueue, ^{
            self->_activeEngine = activeEngine;
        });

        NSError *error;
        if (!self->_configured || self->_configuredPosition != position) {
            if (![self configureSessionForPosition:position error:&error]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.running = NO;
                    [self reportError:error];
                });
                return;
            }
        }
        if (!self->_session.isRunning) [self->_session startRunning];
    });
}

- (BOOL)configureSessionForPosition:(AVCaptureDevicePosition)position error:(NSError **)error {
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                                 mediaType:AVMediaTypeVideo
                                                                  position:position];
    if (!device) device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!device) {
        if (error) *error = [NSError errorWithDomain:FASErrorDomain
                                                code:FASErrorCameraUnavailable
                                            userInfo:@{NSLocalizedDescriptionKey : @"No camera available."}];
        return NO;
    }

    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:error];
    if (!input) return NO;

    [_session beginConfiguration];
    for (AVCaptureInput *existing in _session.inputs) [_session removeInput:existing];
    for (AVCaptureOutput *existing in _session.outputs) [_session removeOutput:existing];

    // 640x480 like the Android sample: plenty for the 192px detector and 80px liveness crops.
    _session.sessionPreset = [_session canSetSessionPreset:AVCaptureSessionPreset640x480]
                                 ? AVCaptureSessionPreset640x480
                                 : AVCaptureSessionPresetHigh;

    if (![_session canAddInput:input]) {
        [_session commitConfiguration];
        if (error) *error = [NSError errorWithDomain:FASErrorDomain
                                                code:FASErrorCameraUnavailable
                                            userInfo:@{NSLocalizedDescriptionKey : @"Cannot use the camera input."}];
        return NO;
    }
    [_session addInput:input];

    _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    _videoOutput.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)};
    _videoOutput.alwaysDiscardsLateVideoFrames = YES;
    [_videoOutput setSampleBufferDelegate:self queue:_videoQueue];
    if (![_session canAddOutput:_videoOutput]) {
        [_session commitConfiguration];
        if (error) *error = [NSError errorWithDomain:FASErrorDomain
                                                code:FASErrorCameraUnavailable
                                            userInfo:@{NSLocalizedDescriptionKey : @"Cannot add the video output."}];
        return NO;
    }
    [_session addOutput:_videoOutput];

    _configuredPosition = device.position;
    [self applyVideoOrientation];
    [_session commitConfiguration];
    _configured = YES;
    return YES;
}

// Frames are delivered upright and mirrored like the preview, so face boxes map directly
// onto the view and the engine always receives FASImageOrientationUp.
- (void)applyVideoOrientation {
    AVCaptureConnection *connection = [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (connection.isVideoOrientationSupported) connection.videoOrientation = _videoOrientation;
    AVCaptureConnection *previewConnection = self.previewLayer.connection;
    if (previewConnection.isVideoOrientationSupported) previewConnection.videoOrientation = _videoOrientation;
#pragma clang diagnostic pop
    if (connection.isVideoMirroringSupported) {
        connection.automaticallyAdjustsVideoMirroring = NO;
        connection.videoMirrored = _configuredPosition == AVCaptureDevicePositionFront;
    }
}

- (AVCaptureVideoOrientation)videoOrientationForInterfaceOrientation:(UIInterfaceOrientation)orientation {
    switch (orientation) {
        case UIInterfaceOrientationPortraitUpsideDown: return AVCaptureVideoOrientationPortraitUpsideDown;
        case UIInterfaceOrientationLandscapeLeft: return AVCaptureVideoOrientationLandscapeLeft;
        case UIInterfaceOrientationLandscapeRight: return AVCaptureVideoOrientationLandscapeRight;
        default: return AVCaptureVideoOrientationPortrait;
    }
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection {
    FASEngine *engine = _activeEngine;
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!engine || !pixelBuffer) return;

    const CFTimeInterval begin = CACurrentMediaTime();
    NSError *error;
    NSArray<FASFace *> *faces = [engine detectFacesInPixelBuffer:pixelBuffer
                                                     orientation:FASImageOrientationUp
                                                           error:&error];
    const NSTimeInterval elapsed = CACurrentMediaTime() - begin;
    if (!faces) return;

    const CGSize imageSize = CGSizeMake(CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer));
    FASFace *face = faces.firstObject;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.running) return;
        CGRect frameInView = face ? [self viewRectForImageRect:face.bounds imageSize:imageSize] : CGRectNull;
        [self updateOverlayWithFace:face frame:frameInView];

        FASLivenessResult *result = [[FASLivenessResult alloc] initWithFace:face
                                                            faceFrameInView:frameInView
                                                                  imageSize:imageSize
                                                             processingTime:elapsed];
        if ([self.delegate respondsToSelector:@selector(livenessCameraView:didProduceResult:)]) {
            [self.delegate livenessCameraView:self didProduceResult:result];
        }
        if (self.resultHandler) self.resultHandler(result);
    });
}

#pragma mark - Helpers

// Maps a rect in image pixels to view points for AVLayerVideoGravityResizeAspectFill.
- (CGRect)viewRectForImageRect:(CGRect)rect imageSize:(CGSize)imageSize {
    const CGSize viewSize = self.bounds.size;
    if (imageSize.width <= 0 || imageSize.height <= 0) return CGRectNull;
    const CGFloat scale = MAX(viewSize.width / imageSize.width, viewSize.height / imageSize.height);
    const CGFloat dx = (viewSize.width - imageSize.width * scale) / 2;
    const CGFloat dy = (viewSize.height - imageSize.height * scale) / 2;
    return CGRectMake(rect.origin.x * scale + dx, rect.origin.y * scale + dy, rect.size.width * scale,
                      rect.size.height * scale);
}

- (void)updateOverlayWithFace:(FASFace *)face frame:(CGRect)frame {
    if (!self.showsFaceOverlay || !face) {
        _overlayLayer.hidden = YES;
        return;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _overlayLayer.hidden = NO;
    _overlayLayer.strokeColor = (face.isLive ? self.liveColor : self.spoofColor).CGColor;
    _overlayLayer.path = [UIBezierPath bezierPathWithRoundedRect:frame cornerRadius:12].CGPath;
    [CATransaction commit];
}

- (void)reportError:(NSInteger)code message:(NSString *)message {
    [self reportError:[NSError errorWithDomain:FASErrorDomain
                                          code:code
                                      userInfo:@{NSLocalizedDescriptionKey : message}]];
}

- (void)reportError:(NSError *)error {
    if ([self.delegate respondsToSelector:@selector(livenessCameraView:didFailWithError:)]) {
        [self.delegate livenessCameraView:self didFailWithError:error];
    }
}

@end
