#import <FaceLivenessSpec/FaceLivenessSpec.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "FASEngine.h"

@interface FaceLivenessModule : NSObject <NativeFaceLivenessSpec>
@end

@implementation FaceLivenessModule

+ (NSString *)moduleName
{
    return @"FaceLiveness";
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeFaceLivenessSpecJSI>(params);
}

// One engine for still images, created on first use. FASEngine is thread-safe.
+ (FASEngine *)sharedEngine:(NSError **)error
{
    static FASEngine *engine;
    static NSError *loadError;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSError *e;
        engine = [FASEngine bundledEngineWithError:&e];
        loadError = e;
    });
    if (!engine && error) *error = loadError;
    return engine;
}

- (void)detectInFile:(NSString *)path
   livenessThreshold:(double)livenessThreshold
            allFaces:(BOOL)allFaces
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *filePath = path;
        if ([path hasPrefix:@"file://"]) filePath = [NSURL URLWithString:path].path ?: path;

        UIImage *image = [UIImage imageWithContentsOfFile:filePath];
        if (!image) {
            reject(@"invalid-image", [NSString stringWithFormat:@"Could not read an image at %@", path], nil);
            return;
        }

        NSError *error;
        FASEngine *engine = [FaceLivenessModule sharedEngine:&error];
        if (!engine) {
            reject(@"engine-error", error.localizedDescription ?: @"Failed to load the models.", error);
            return;
        }

        // The shared engine may be used concurrently, so judge liveness here with the
        // caller's threshold instead of mutating engine.livenessThreshold.
        NSArray<FASFace *> *faces;
        @synchronized(engine) {
            BOOL previous = engine.evaluatesAllFaces;
            engine.evaluatesAllFaces = allFaces;
            faces = [engine detectFacesInImage:image error:&error];
            engine.evaluatesAllFaces = previous;
        }
        if (!faces) {
            reject(@"detection-error", error.localizedDescription ?: @"Detection failed.", error);
            return;
        }

        NSMutableArray *result = [NSMutableArray arrayWithCapacity:faces.count];
        for (FASFace *face in faces) {
            [result addObject:@{
                @"x" : @(face.bounds.origin.x),
                @"y" : @(face.bounds.origin.y),
                @"width" : @(face.bounds.size.width),
                @"height" : @(face.bounds.size.height),
                @"detectionConfidence" : @(face.detectionConfidence),
                @"livenessScore" : @(face.livenessScore),
                @"isLive" : @(face.livenessScore >= livenessThreshold),
            }];
        }
        resolve(result);
    });
}

@end
