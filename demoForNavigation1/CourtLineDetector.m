//
//  CourtLineDetector.m
//  demoForNavigation1
//
//  Basketball court line detection using Vision framework
//  Applies geometric rules to identify straight lines and arcs typical of basketball courts
//

#import "CourtLineDetector.h"

@implementation DetectedCourtLine
@end

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
        _detectDarkOnLight = YES;  // Detect dark lines on light background (try both)
        _minLineLength = 0.05;    // Minimum 5% of image dimension (more lenient)
        _angleThreshold = 35.0;   // 35 degrees tolerance for horizontal/vertical (more lenient)
        _straightnessThreshold = 0.75;  // 75% straightness required (more lenient)
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
        [self detectLinesInPixelBuffer:pixelBuffer];
    }
}

#pragma mark - Line Detection

- (void)detectLinesInPixelBuffer:(CVPixelBufferRef)pixelBuffer API_AVAILABLE(ios(14.0)) {
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    self.lastImageSize = CGSizeMake(width, height);

    // Create contour detection request
    VNDetectContoursRequest *contoursRequest = [[VNDetectContoursRequest alloc] init];
    contoursRequest.contrastAdjustment = self.contrastAdjustment;
    contoursRequest.detectsDarkOnLight = self.detectDarkOnLight;
    contoursRequest.maximumImageDimension = 512;

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

    // Process and classify contours
    NSMutableArray<DetectedCourtLine *> *detectedLines = [NSMutableArray array];

    for (VNContoursObservation *observation in contoursRequest.results) {
        NSInteger topLevelCount = observation.topLevelContourCount;

        for (NSInteger i = 0; i < topLevelCount && detectedLines.count < 50; i++) {
            NSError *contourError = nil;
            VNContour *contour = [observation contourAtIndex:i error:&contourError];

            if (contourError || !contour) continue;

            // Analyze and classify this contour
            DetectedCourtLine *line = [self analyzeContour:contour];
            if (line && line.lineType != CourtLineTypeUnknown) {
                [detectedLines addObject:line];
            }

            // Also check child contours
            [self processChildContours:contour toArray:detectedLines depth:0];
        }
    }

    // Notify delegate on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(courtLinesDetected:imageSize:)]) {
            [self.delegate courtLinesDetected:detectedLines imageSize:self.lastImageSize];
        }
    });
}

- (void)processChildContours:(VNContour *)parentContour
                     toArray:(NSMutableArray<DetectedCourtLine *> *)array
                       depth:(NSInteger)depth API_AVAILABLE(ios(14.0)) {
    if (depth > 2 || array.count >= 50) return;

    NSInteger childCount = parentContour.childContourCount;
    for (NSInteger i = 0; i < childCount && array.count < 50; i++) {
        NSError *error = nil;
        VNContour *child = [parentContour childContourAtIndex:i error:&error];

        if (error || !child) continue;

        DetectedCourtLine *line = [self analyzeContour:child];
        if (line && line.lineType != CourtLineTypeUnknown) {
            [array addObject:line];
        }

        [self processChildContours:child toArray:array depth:depth + 1];
    }
}

#pragma mark - Contour Analysis

- (DetectedCourtLine *)analyzeContour:(VNContour *)contour API_AVAILABLE(ios(14.0)) {
    if (contour.pointCount < 4) {
        return nil;
    }

    // Get points from the contour
    NSArray<NSValue *> *points = [self extractPointsFromContour:contour];
    if (points.count < 4) {
        return nil;
    }

    // Calculate basic metrics
    CGFloat totalLength = [self calculatePathLength:points];

    // Filter by minimum length
    if (totalLength < self.minLineLength) {
        return nil;
    }

    // Get start and end points
    CGPoint startPoint = [points.firstObject CGPointValue];
    CGPoint endPoint = [points.lastObject CGPointValue];

    // Calculate direct distance between start and end
    CGFloat directDistance = [self distanceFrom:startPoint to:endPoint];

    // Calculate straightness (ratio of direct distance to path length)
    // A perfectly straight line has straightness = 1.0
    CGFloat straightness = (totalLength > 0) ? (directDistance / totalLength) : 0;

    // Analyze line characteristics
    DetectedCourtLine *line = [[DetectedCourtLine alloc] init];
    line.length = totalLength;
    line.straightness = straightness;
    line.startPoint = startPoint;
    line.endPoint = endPoint;

    // Classify the line based on straightness
    CGFloat angle = [self angleOfLineFrom:startPoint to:endPoint];
    line.angle = angle;

    if (straightness >= self.straightnessThreshold) {
        // This is a straight line - classify by angle
        // Check if horizontal (0° or 180° ± threshold)
        if ([self isAngleHorizontal:angle]) {
            line.lineType = CourtLineTypeHorizontal;
        }
        // Check if vertical (90° or 270° ± threshold)
        else if ([self isAngleVertical:angle]) {
            line.lineType = CourtLineTypeVertical;
        }
        else {
            // Diagonal lines - still show as horizontal for visibility
            // (camera angle can make court lines appear diagonal)
            line.lineType = CourtLineTypeHorizontal;
        }
    }
    else if (straightness >= 0.3) {
        // This might be an arc (curved but not too random)
        // More lenient threshold for arcs
        line.lineType = CourtLineTypeArc;
    }
    else {
        // Too irregular - but still might be a partial line, show as arc
        line.lineType = CourtLineTypeArc;
    }

    // Create the path
    line.path = [self createPathFromContour:contour];

    return line;
}

- (NSArray<NSValue *> *)extractPointsFromContour:(VNContour *)contour API_AVAILABLE(ios(14.0)) {
    NSMutableArray<NSValue *> *points = [NSMutableArray array];

    // Simplify contour first for cleaner analysis
    VNContour *simplified = [contour polygonApproximationWithEpsilon:0.005 error:nil];
    if (!simplified) {
        simplified = contour;
    }

    CGPathRef path = simplified.normalizedPath;
    if (!path) {
        return points;
    }

    // Extract points from the path
    CGPathApply(path, (__bridge void *)points, extractPathPoints);

    return points;
}

void extractPathPoints(void *info, const CGPathElement *element) {
    NSMutableArray<NSValue *> *points = (__bridge NSMutableArray<NSValue *> *)info;

    switch (element->type) {
        case kCGPathElementMoveToPoint:
        case kCGPathElementAddLineToPoint:
            [points addObject:[NSValue valueWithCGPoint:element->points[0]]];
            break;
        case kCGPathElementAddQuadCurveToPoint:
            [points addObject:[NSValue valueWithCGPoint:element->points[0]]];
            [points addObject:[NSValue valueWithCGPoint:element->points[1]]];
            break;
        case kCGPathElementAddCurveToPoint:
            [points addObject:[NSValue valueWithCGPoint:element->points[0]]];
            [points addObject:[NSValue valueWithCGPoint:element->points[1]]];
            [points addObject:[NSValue valueWithCGPoint:element->points[2]]];
            break;
        case kCGPathElementCloseSubpath:
            break;
    }
}

- (UIBezierPath *)createPathFromContour:(VNContour *)contour API_AVAILABLE(ios(14.0)) {
    VNContour *simplified = [contour polygonApproximationWithEpsilon:0.003 error:nil];
    if (!simplified) {
        simplified = contour;
    }

    CGPathRef cgPath = simplified.normalizedPath;
    if (cgPath) {
        return [UIBezierPath bezierPathWithCGPath:cgPath];
    }
    return nil;
}

#pragma mark - Geometry Calculations

- (CGFloat)calculatePathLength:(NSArray<NSValue *> *)points {
    if (points.count < 2) return 0;

    CGFloat length = 0;
    CGPoint prevPoint = [points[0] CGPointValue];

    for (NSInteger i = 1; i < points.count; i++) {
        CGPoint currentPoint = [points[i] CGPointValue];
        length += [self distanceFrom:prevPoint to:currentPoint];
        prevPoint = currentPoint;
    }

    return length;
}

- (CGFloat)distanceFrom:(CGPoint)p1 to:(CGPoint)p2 {
    CGFloat dx = p2.x - p1.x;
    CGFloat dy = p2.y - p1.y;
    return sqrt(dx * dx + dy * dy);
}

- (CGFloat)angleOfLineFrom:(CGPoint)p1 to:(CGPoint)p2 {
    CGFloat dx = p2.x - p1.x;
    CGFloat dy = p2.y - p1.y;
    CGFloat radians = atan2(dy, dx);
    CGFloat degrees = radians * 180.0 / M_PI;

    // Normalize to 0-360
    if (degrees < 0) {
        degrees += 360;
    }
    return degrees;
}

- (BOOL)isAngleHorizontal:(CGFloat)angle {
    // Horizontal: 0°, 180°, 360° (± threshold)
    CGFloat threshold = self.angleThreshold;

    if (angle <= threshold || angle >= (360 - threshold)) {
        return YES;  // Near 0° or 360°
    }
    if (angle >= (180 - threshold) && angle <= (180 + threshold)) {
        return YES;  // Near 180°
    }
    return NO;
}

- (BOOL)isAngleVertical:(CGFloat)angle {
    // Vertical: 90°, 270° (± threshold)
    CGFloat threshold = self.angleThreshold;

    if (angle >= (90 - threshold) && angle <= (90 + threshold)) {
        return YES;  // Near 90°
    }
    if (angle >= (270 - threshold) && angle <= (270 + threshold)) {
        return YES;  // Near 270°
    }
    return NO;
}

- (BOOL)hasConsistentCurvature:(NSArray<NSValue *> *)points {
    if (points.count < 5) return NO;

    // Calculate curvature at multiple points along the path
    // Curvature should be relatively consistent for arcs
    NSMutableArray<NSNumber *> *curvatures = [NSMutableArray array];

    for (NSInteger i = 1; i < points.count - 1; i++) {
        CGPoint p0 = [points[i-1] CGPointValue];
        CGPoint p1 = [points[i] CGPointValue];
        CGPoint p2 = [points[i+1] CGPointValue];

        CGFloat curvature = [self curvatureAtPoint:p1 withPrev:p0 andNext:p2];
        if (!isnan(curvature) && !isinf(curvature)) {
            [curvatures addObject:@(curvature)];
        }
    }

    if (curvatures.count < 3) return NO;

    // Calculate variance of curvature
    CGFloat sum = 0;
    for (NSNumber *c in curvatures) {
        sum += c.floatValue;
    }
    CGFloat mean = sum / curvatures.count;

    CGFloat variance = 0;
    for (NSNumber *c in curvatures) {
        CGFloat diff = c.floatValue - mean;
        variance += diff * diff;
    }
    variance /= curvatures.count;

    // Low variance means consistent curvature (good for arcs)
    // Also check that mean curvature is non-zero (it's actually curved)
    CGFloat stdDev = sqrt(variance);

    // For an arc, we want:
    // 1. Non-zero mean curvature (it's actually curved)
    // 2. Low standard deviation relative to mean (consistent curve)
    BOOL isCurved = fabs(mean) > 0.5;  // Has some curvature
    BOOL isConsistent = (fabs(mean) > 0.01) ? (stdDev / fabs(mean) < 2.0) : (stdDev < 1.0);

    return isCurved && isConsistent;
}

- (CGFloat)curvatureAtPoint:(CGPoint)p1 withPrev:(CGPoint)p0 andNext:(CGPoint)p2 {
    // Calculate curvature using the formula:
    // k = 2 * |cross product| / (|p0-p1| * |p1-p2| * |p0-p2|)

    CGFloat ax = p1.x - p0.x;
    CGFloat ay = p1.y - p0.y;
    CGFloat bx = p2.x - p1.x;
    CGFloat by = p2.y - p1.y;

    CGFloat cross = ax * by - ay * bx;

    CGFloat d01 = sqrt(ax * ax + ay * ay);
    CGFloat d12 = sqrt(bx * bx + by * by);
    CGFloat d02 = [self distanceFrom:p0 to:p2];

    CGFloat denominator = d01 * d12 * d02;
    if (denominator < 0.0001) {
        return 0;
    }

    return 2.0 * fabs(cross) / denominator;
}

@end
