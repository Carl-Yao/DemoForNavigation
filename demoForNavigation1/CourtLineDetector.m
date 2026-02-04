//
//  CourtLineDetector.m
//  demoForNavigation1
//
//  Basketball court line detection using Vision and Core Image
//

#import "CourtLineDetector.h"

@interface CourtLineDetector ()

@property (nonatomic, assign) BOOL isDetecting;
@property (nonatomic, assign) NSInteger frameCount;
@property (nonatomic, assign) CGSize lastImageSize;

@end

@implementation CourtLineDetector

- (instancetype)init {
    self = [super init];
    if (self) {
        _isDetecting = NO;
        _frameCount = 0;
        _contrastAdjustment = 2.0;
        _simplificationEpsilon = 0.002;
        _detectDarkOnLight = YES;
        _lastImageSize = CGSizeZero;
    }
    return self;
}

- (void)startDetection {
    self.isDetecting = YES;
    self.frameCount = 0;
}

- (void)stopDetection {
    self.isDetecting = NO;
}

- (void)processPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!self.isDetecting) {
        return;
    }

    // Process every 3rd frame for performance
    self.frameCount++;
    if (self.frameCount % 3 != 0) {
        return;
    }

    if (@available(iOS 14.0, *)) {
        [self detectContoursInPixelBuffer:pixelBuffer];
    }
}

- (void)detectContoursInPixelBuffer:(CVPixelBufferRef)pixelBuffer API_AVAILABLE(ios(14.0)) {
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    self.lastImageSize = CGSizeMake(width, height);

    // Create contour detection request
    VNDetectContoursRequest *contoursRequest = [[VNDetectContoursRequest alloc] init];
    contoursRequest.contrastAdjustment = self.contrastAdjustment;
    contoursRequest.detectsDarkOnLight = self.detectDarkOnLight;
    contoursRequest.maximumImageDimension = 512; // Reduce for performance

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer options:@{}];

    NSError *error = nil;
    [handler performRequests:@[contoursRequest] error:&error];

    if (error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(courtLineDetectionFailed:)]) {
                [self.delegate courtLineDetectionFailed:error.localizedDescription];
            }
        });
        return;
    }

    // Process results
    NSMutableArray<UIBezierPath *> *contourPaths = [NSMutableArray array];
    NSInteger totalContours = 0;

    for (VNContoursObservation *observation in contoursRequest.results) {
        totalContours += observation.contourCount;

        // Get top-level contours
        NSInteger topLevelCount = observation.topLevelContourCount;
        for (NSInteger i = 0; i < topLevelCount && i < 30; i++) { // Limit to 30 contours
            NSError *contourError = nil;
            VNContour *contour = [observation contourAtIndex:i error:&contourError];

            if (contourError || !contour) continue;

            // Filter by point count (ignore very small contours)
            if (contour.pointCount < 10) continue;

            // Simplify the contour path
            VNContour *simplifiedContour = [contour polygonApproximationWithEpsilon:self.simplificationEpsilon error:nil];
            if (!simplifiedContour) {
                simplifiedContour = contour;
            }

            // Convert to UIBezierPath
            CGPathRef cgPath = simplifiedContour.normalizedPath;
            if (cgPath) {
                UIBezierPath *path = [UIBezierPath bezierPathWithCGPath:cgPath];
                [contourPaths addObject:path];
            }

            // Also process child contours (nested lines)
            [self addChildContours:contour toArray:contourPaths depth:0];
        }
    }

    // Notify delegate on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(courtLinesDetectedWithContours:lineCount:imageSize:)]) {
            [self.delegate courtLinesDetectedWithContours:contourPaths
                                                lineCount:contourPaths.count
                                                imageSize:self.lastImageSize];
        }
    });
}

- (void)addChildContours:(VNContour *)parentContour toArray:(NSMutableArray<UIBezierPath *> *)array depth:(NSInteger)depth API_AVAILABLE(ios(14.0)) {
    if (depth > 2) return; // Limit recursion depth

    NSInteger childCount = parentContour.childContourCount;
    for (NSInteger i = 0; i < childCount && array.count < 50; i++) {
        NSError *error = nil;
        VNContour *child = [parentContour childContourAtIndex:i error:&error];

        if (error || !child) continue;
        if (child.pointCount < 8) continue;

        VNContour *simplified = [child polygonApproximationWithEpsilon:self.simplificationEpsilon error:nil];
        if (!simplified) simplified = child;

        CGPathRef cgPath = simplified.normalizedPath;
        if (cgPath) {
            UIBezierPath *path = [UIBezierPath bezierPathWithCGPath:cgPath];
            [array addObject:path];
        }

        // Recursively add grandchildren
        [self addChildContours:child toArray:array depth:depth + 1];
    }
}

@end
