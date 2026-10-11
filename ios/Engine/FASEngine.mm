//
//  FASEngine.mm
//  FaceAntiSpoofing
//

#import "FASEngine.h"

#include <mutex>
#include <vector>

#include "fas/face_anti_spoofing.h"

NSErrorDomain const FASErrorDomain = @"FASErrorDomain";

static NSString *const kModelBundleName = @"FaceAntiSpoofingModels";

static NSError *FASMakeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:FASErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey : message}];
}

static NSString *FASMessageForStatus(int status) {
    switch (status) {
        case fas::kErrorNotLoaded: return @"Models are not loaded.";
        case fas::kErrorInvalidImage: return @"Invalid image.";
        case fas::kErrorInvalidConfig: return @"Invalid liveness model config.";
        case fas::kErrorLoadDetector: return @"Failed to load the face detection model.";
        case fas::kErrorLoadLiveness: return @"Failed to load the liveness models.";
        default: return [NSString stringWithFormat:@"Engine error %d.", status];
    }
}

@implementation FASFace

- (instancetype)initWithBounds:(CGRect)bounds
           detectionConfidence:(float)detectionConfidence
                 livenessScore:(float)livenessScore
                          live:(BOOL)live {
    if ((self = [super init])) {
        _bounds = bounds;
        _detectionConfidence = detectionConfidence;
        _livenessScore = livenessScore;
        _live = live;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<FASFace bounds=%@ detection=%.3f liveness=%.4f live=%@>",
                                      NSStringFromCGRect(_bounds), _detectionConfidence,
                                      _livenessScore, _live ? @"YES" : @"NO"];
}

@end

@implementation FASEngine {
    fas::Engine _engine;
    std::mutex _mutex;
    std::vector<fas::Face> _faces;
}

+ (float)defaultLivenessThreshold {
    return 0.915f;
}

+ (NSBundle *)modelBundle {
    static NSBundle *bundle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
#if defined(SWIFTPM_MODULE_BUNDLE)
        // Swift Package Manager: models are resources of this target.
        bundle = SWIFTPM_MODULE_BUNDLE;
        if (bundle) return;
#endif
        // CocoaPods: models live in FaceAntiSpoofingModels.bundle.
        NSArray<NSBundle *> *candidates = @[ [NSBundle bundleForClass:FASEngine.class], NSBundle.mainBundle ];
        for (NSBundle *candidate in candidates) {
            NSString *path = [candidate pathForResource:kModelBundleName ofType:@"bundle"];
            if (path) {
                bundle = [NSBundle bundleWithPath:path];
                break;
            }
        }
    });
    return bundle;
}

+ (instancetype)bundledEngineWithError:(NSError **)error {
    NSBundle *bundle = FASEngine.modelBundle;
    if (!bundle) {
        if (error) *error = FASMakeError(FASErrorModelsNotFound, @"FaceAntiSpoofing model bundle not found.");
        return nil;
    }
    return [[self alloc] initWithModelDirectory:bundle.resourcePath error:error];
}

- (instancetype)initWithModelDirectory:(NSString *)directory error:(NSError **)error {
    if ((self = [super init])) {
        _livenessThreshold = FASEngine.defaultLivenessThreshold;
        _minFaceSize = 64;
        _faceDetectionThreshold = 0.6f;
        _numThreads = 2;
        _evaluatesAllFaces = NO;

        _engine.SetNumThreads((int)_numThreads);
        int status = _engine.LoadFromDirectory(directory.fileSystemRepresentation);
        if (status != fas::kOk) {
            if (error) *error = FASMakeError(status, FASMessageForStatus(status));
            return nil;
        }
    }
    return self;
}

#pragma mark - Detection

- (NSArray<FASFace *> *)detectWithImage:(const fas::Image &)image error:(NSError **)error {
    const float threshold = self.livenessThreshold;
    const int minFaceSize = (int)self.minFaceSize;
    const float detectionThreshold = self.faceDetectionThreshold;
    const int numThreads = (int)MAX(1, self.numThreads);
    const bool allFaces = self.evaluatesAllFaces;

    std::lock_guard<std::mutex> lock(_mutex);
    _engine.face_detector().SetMinFaceSize(minFaceSize);
    _engine.face_detector().SetThreshold(detectionThreshold);
    _engine.SetNumThreads(numThreads);

    int status = _engine.Detect(image, _faces, allFaces);
    if (status != fas::kOk) {
        if (error) *error = FASMakeError(status, FASMessageForStatus(status));
        return nil;
    }

    NSMutableArray<FASFace *> *result = [NSMutableArray arrayWithCapacity:_faces.size()];
    for (const auto &face : _faces) {
        CGRect bounds = CGRectMake(face.box.x1, face.box.y1, face.box.x2 - face.box.x1 + 1,
                                   face.box.y2 - face.box.y1 + 1);
        [result addObject:[[FASFace alloc] initWithBounds:bounds
                                      detectionConfidence:face.box.confidence
                                            livenessScore:face.liveness
                                                     live:face.liveness >= threshold]];
    }
    return result;
}

- (NSArray<FASFace *> *)detectFacesInBytes:(const void *)bytes
                                     width:(NSInteger)width
                                    height:(NSInteger)height
                               bytesPerRow:(NSInteger)bytesPerRow
                               pixelFormat:(FASPixelFormat)pixelFormat
                               orientation:(FASImageOrientation)orientation
                                     error:(NSError **)error {
    fas::Image image;
    image.data = static_cast<const uint8_t *>(bytes);
    image.width = (int)width;
    image.height = (int)height;
    image.stride = (int)bytesPerRow;
    image.orientation = (int)orientation;
    switch (pixelFormat) {
        case FASPixelFormatRGBA: image.format = fas::PixelFormat::kRGBA; break;
        case FASPixelFormatBGRA: image.format = fas::PixelFormat::kBGRA; break;
        case FASPixelFormatRGB: image.format = fas::PixelFormat::kRGB; break;
        case FASPixelFormatBGR: image.format = fas::PixelFormat::kBGR; break;
        case FASPixelFormatNV21: image.format = fas::PixelFormat::kNV21; break;
        case FASPixelFormatNV12: image.format = fas::PixelFormat::kNV12; break;
        default:
            if (error) *error = FASMakeError(FASErrorUnsupportedPixelFormat, @"Unsupported pixel format.");
            return nil;
    }
    return [self detectWithImage:image error:error];
}

- (NSArray<FASFace *> *)detectFacesInPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                     orientation:(FASImageOrientation)orientation
                                           error:(NSError **)error {
    if (!pixelBuffer) {
        if (error) *error = FASMakeError(FASErrorInvalidImage, @"Pixel buffer is NULL.");
        return nil;
    }

    const OSType type = CVPixelBufferGetPixelFormatType(pixelBuffer);
    const BOOL biPlanar = type == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
                          type == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
    if (type != kCVPixelFormatType_32BGRA && !biPlanar) {
        if (error) {
            *error = FASMakeError(FASErrorUnsupportedPixelFormat,
                                  @"Only kCVPixelFormatType_32BGRA and 420 bi-planar pixel buffers are supported.");
        }
        return nil;
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    NSArray<FASFace *> *faces;
    const size_t width = CVPixelBufferGetWidth(pixelBuffer);
    const size_t height = CVPixelBufferGetHeight(pixelBuffer);

    if (!biPlanar) {
        faces = [self detectFacesInBytes:CVPixelBufferGetBaseAddress(pixelBuffer)
                                   width:width
                                  height:height
                             bytesPerRow:CVPixelBufferGetBytesPerRow(pixelBuffer)
                             pixelFormat:FASPixelFormatBGRA
                             orientation:orientation
                                   error:error];
    } else {
        // Pack the (possibly padded, non adjacent) planes into one contiguous NV12 buffer.
        std::vector<uint8_t> nv12(width * height * 3 / 2);
        const uint8_t *y = static_cast<const uint8_t *>(CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0));
        const uint8_t *uv = static_cast<const uint8_t *>(CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1));
        const size_t yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
        const size_t uvStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
        for (size_t row = 0; row < height; ++row) {
            memcpy(nv12.data() + row * width, y + row * yStride, width);
        }
        uint8_t *uvDst = nv12.data() + width * height;
        for (size_t row = 0; row < height / 2; ++row) {
            memcpy(uvDst + row * width, uv + row * uvStride, width);
        }
        faces = [self detectFacesInBytes:nv12.data()
                                   width:width
                                  height:height
                             bytesPerRow:width
                             pixelFormat:FASPixelFormatNV12
                             orientation:orientation
                                   error:error];
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    return faces;
}

- (NSArray<FASFace *> *)detectFacesInImage:(UIImage *)image error:(NSError **)error {
    const size_t width = (size_t)llround(image.size.width * image.scale);
    const size_t height = (size_t)llround(image.size.height * image.scale);
    if (width == 0 || height == 0) {
        if (error) *error = FASMakeError(FASErrorInvalidImage, @"Image is empty.");
        return nil;
    }

    // Render upright (honours imageOrientation) into a tightly packed RGBA buffer.
    std::vector<uint8_t> pixels(width * height * 4);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels.data(), width, height, 8, width * 4, colorSpace,
                                                 kCGImageAlphaNoneSkipLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        if (error) *error = FASMakeError(FASErrorInvalidImage, @"Could not create a bitmap context.");
        return nil;
    }
    CGContextTranslateCTM(context, 0, height);
    CGContextScaleCTM(context, 1, -1);
    UIGraphicsPushContext(context);
    [image drawInRect:CGRectMake(0, 0, width, height)];
    UIGraphicsPopContext();
    CGContextRelease(context);

    return [self detectFacesInBytes:pixels.data()
                              width:width
                             height:height
                        bytesPerRow:width * 4
                        pixelFormat:FASPixelFormatRGBA
                        orientation:FASImageOrientationUp
                              error:error];
}

@end
