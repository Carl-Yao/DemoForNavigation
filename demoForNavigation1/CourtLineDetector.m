//
//  CourtLineDetector.m
//  demoForNavigation1
//
//  Basketball court line detection based on FIBA half-court geometry
//  FIBA Half-court: 15m width x 14m length
//  Key lines: baseline, half-court line, sidelines, free throw line, lane lines, three-point arc
//

#import "CourtLineDetector.h"

@implementation DetectedLine
@end

@implementation DetectedCourt
- (instancetype)init {
    self = [super init];
    if (self) {
        _horizontalLines = @[];
        _verticalLines = @[];
        _arcLines = @[];
        _isCourtDetected = NO;
        _courtBounds = CGRectZero;
    }
    return self;
}
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
        _contrastAdjustment = 1.5;
        _minLineLength = 0.08;      // 8% of image dimension
        _angleThreshold = 20.0;     // 20 degrees tolerance
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
    if (!self.isDetecting) return;

    self.frameCount++;
    if (self.frameCount % 3 != 0) return;  // Process every 3rd frame

    if (@available(iOS 14.0, *)) {
        [self detectCourtLinesInPixelBuffer:pixelBuffer];
    }
}

#pragma mark - Court Detection

- (void)detectCourtLinesInPixelBuffer:(CVPixelBufferRef)pixelBuffer API_AVAILABLE(ios(14.0)) {
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);

    // Camera is landscape, phone is portrait - swap dimensions
    self.lastImageSize = CGSizeMake(height, width);

    // Create contour detection request
    VNDetectContoursRequest *request = [[VNDetectContoursRequest alloc] init];
    request.contrastAdjustment = self.contrastAdjustment;
    request.detectsDarkOnLight = NO;  // Detect light lines on dark court
    request.maximumImageDimension = 512;

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer options:@{}];

    NSError *error = nil;
    [handler performRequests:@[request] error:&error];

    if (error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate courtLineDetectionFailed:error.localizedDescription];
        });
        return;
    }

    // Extract and analyze contours
    NSMutableArray<DetectedLine *> *allLines = [NSMutableArray array];

    for (VNContoursObservation *observation in request.results) {
        [self extractLinesFromObservation:observation toArray:allLines];
    }

    // Classify lines and match to court geometry
    DetectedCourt *court = [self matchCourtGeometry:allLines];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate courtLineDetector:self didDetectCourt:court inImageSize:self.lastImageSize];
    });
}

- (void)extractLinesFromObservation:(VNContoursObservation *)observation
                            toArray:(NSMutableArray<DetectedLine *> *)lines API_AVAILABLE(ios(14.0)) {
    NSInteger count = observation.topLevelContourCount;

    for (NSInteger i = 0; i < count && lines.count < 100; i++) {
        NSError *error = nil;
        VNContour *contour = [observation contourAtIndex:i error:&error];
        if (error || !contour) continue;

        // Simplify contour for analysis
        VNContour *simplified = [contour polygonApproximationWithEpsilon:0.01 error:nil];
        if (!simplified) simplified = contour;

        // Extract points and analyze
        NSArray<NSValue *> *points = [self extractPointsFromContour:simplified];
        if (points.count < 2) continue;

        // Try to fit a line to these points
        DetectedLine *line = [self fitLineToPoints:points];
        if (line && line.length >= self.minLineLength) {
            [lines addObject:line];
        }

        // Also check child contours
        [self extractChildContours:contour toArray:lines depth:0];
    }
}

- (void)extractChildContours:(VNContour *)parent
                     toArray:(NSMutableArray<DetectedLine *> *)lines
                       depth:(NSInteger)depth API_AVAILABLE(ios(14.0)) {
    if (depth > 2 || lines.count >= 100) return;

    NSInteger childCount = parent.childContourCount;
    for (NSInteger i = 0; i < childCount && lines.count < 100; i++) {
        NSError *error = nil;
        VNContour *child = [parent childContourAtIndex:i error:&error];
        if (error || !child) continue;

        VNContour *simplified = [child polygonApproximationWithEpsilon:0.01 error:nil];
        if (!simplified) simplified = child;

        NSArray<NSValue *> *points = [self extractPointsFromContour:simplified];
        if (points.count >= 2) {
            DetectedLine *line = [self fitLineToPoints:points];
            if (line && line.length >= self.minLineLength) {
                [lines addObject:line];
            }
        }

        [self extractChildContours:child toArray:lines depth:depth + 1];
    }
}

- (NSArray<NSValue *> *)extractPointsFromContour:(VNContour *)contour API_AVAILABLE(ios(14.0)) {
    NSMutableArray<NSValue *> *points = [NSMutableArray array];

    CGPathRef path = contour.normalizedPath;
    if (!path) return points;

    // Use path apply to extract points
    CGPathApply(path, (__bridge void *)points, pathApplyCallback);

    return points;
}

void pathApplyCallback(void *info, const CGPathElement *element) {
    NSMutableArray<NSValue *> *points = (__bridge NSMutableArray *)info;

    switch (element->type) {
        case kCGPathElementMoveToPoint:
        case kCGPathElementAddLineToPoint:
            [points addObject:[NSValue valueWithCGPoint:element->points[0]]];
            break;
        case kCGPathElementAddQuadCurveToPoint:
            [points addObject:[NSValue valueWithCGPoint:element->points[1]]];
            break;
        case kCGPathElementAddCurveToPoint:
            [points addObject:[NSValue valueWithCGPoint:element->points[2]]];
            break;
        default:
            break;
    }
}

#pragma mark - Line Fitting

- (DetectedLine *)fitLineToPoints:(NSArray<NSValue *> *)points {
    if (points.count < 2) return nil;

    // Get start and end points
    CGPoint start = [points.firstObject CGPointValue];
    CGPoint end = [points.lastObject CGPointValue];

    // Calculate path length
    CGFloat pathLength = 0;
    for (NSInteger i = 1; i < points.count; i++) {
        CGPoint p1 = [points[i-1] CGPointValue];
        CGPoint p2 = [points[i] CGPointValue];
        pathLength += hypot(p2.x - p1.x, p2.y - p1.y);
    }

    // Calculate direct distance
    CGFloat directDist = hypot(end.x - start.x, end.y - start.y);

    // Check straightness (direct distance / path length)
    CGFloat straightness = (pathLength > 0) ? (directDist / pathLength) : 0;

    // Only accept relatively straight contours as lines
    if (straightness < 0.7) return nil;

    // Create detected line
    DetectedLine *line = [[DetectedLine alloc] init];
    line.startPoint = start;
    line.endPoint = end;
    line.length = directDist;

    // Calculate angle (0-180 degrees)
    CGFloat dx = end.x - start.x;
    CGFloat dy = end.y - start.y;
    CGFloat angle = atan2(dy, dx) * 180.0 / M_PI;
    if (angle < 0) angle += 180;
    if (angle >= 180) angle -= 180;
    line.angle = angle;

    // Classify as horizontal or vertical
    // Note: Phone is portrait, camera is landscape, so axes are swapped
    // Horizontal in image = near 0° or 180°
    // Vertical in image = near 90°
    CGFloat threshold = self.angleThreshold;

    line.isHorizontal = (angle <= threshold) || (angle >= 180 - threshold);
    line.isVertical = (angle >= 90 - threshold) && (angle <= 90 + threshold);

    line.lineType = CourtLineTypeOther;

    return line;
}

#pragma mark - Court Geometry Matching

- (DetectedCourt *)matchCourtGeometry:(NSArray<DetectedLine *> *)lines {
    DetectedCourt *court = [[DetectedCourt alloc] init];

    // Separate horizontal and vertical lines
    NSMutableArray<DetectedLine *> *horizontals = [NSMutableArray array];
    NSMutableArray<DetectedLine *> *verticals = [NSMutableArray array];
    NSMutableArray<DetectedLine *> *others = [NSMutableArray array];

    for (DetectedLine *line in lines) {
        if (line.isHorizontal) {
            [horizontals addObject:line];
        } else if (line.isVertical) {
            [verticals addObject:line];
        } else {
            [others addObject:line];
        }
    }

    // Sort horizontal lines by Y position (top to bottom in normalized coords)
    [horizontals sortUsingComparator:^NSComparisonResult(DetectedLine *a, DetectedLine *b) {
        CGFloat yA = (a.startPoint.y + a.endPoint.y) / 2;
        CGFloat yB = (b.startPoint.y + b.endPoint.y) / 2;
        return yA < yB ? NSOrderedAscending : NSOrderedDescending;
    }];

    // Sort vertical lines by X position (left to right)
    [verticals sortUsingComparator:^NSComparisonResult(DetectedLine *a, DetectedLine *b) {
        CGFloat xA = (a.startPoint.x + a.endPoint.x) / 2;
        CGFloat xB = (b.startPoint.x + b.endPoint.x) / 2;
        return xA < xB ? NSOrderedAscending : NSOrderedDescending;
    }];

    // Try to identify court lines based on FIBA geometry
    // Looking for: 2-3 horizontal lines, 2-4 vertical lines

    if (horizontals.count >= 2 && verticals.count >= 2) {
        // Find the longest horizontal lines (likely baseline and half-court line)
        NSArray<DetectedLine *> *sortedByLength = [horizontals sortedArrayUsingComparator:^NSComparisonResult(DetectedLine *a, DetectedLine *b) {
            return a.length > b.length ? NSOrderedAscending : NSOrderedDescending;
        }];

        // Top 2 longest horizontals could be baseline and half-court line
        if (sortedByLength.count >= 2) {
            DetectedLine *line1 = sortedByLength[0];
            DetectedLine *line2 = sortedByLength[1];

            // Determine which is baseline (bottom) and which is half-court (top)
            CGFloat y1 = (line1.startPoint.y + line1.endPoint.y) / 2;
            CGFloat y2 = (line2.startPoint.y + line2.endPoint.y) / 2;

            if (y1 < y2) {
                line1.lineType = CourtLineTypeHalfCourtLine;
                line2.lineType = CourtLineTypeBaseline;
            } else {
                line1.lineType = CourtLineTypeBaseline;
                line2.lineType = CourtLineTypeHalfCourtLine;
            }
        }

        // Find outermost vertical lines (sidelines)
        if (verticals.count >= 2) {
            verticals.firstObject.lineType = CourtLineTypeSideline;
            verticals.lastObject.lineType = CourtLineTypeSideline;

            // Inner verticals could be lane lines
            for (NSInteger i = 1; i < verticals.count - 1; i++) {
                verticals[i].lineType = CourtLineTypeLaneLine;
            }
        }

        // Check for free throw line (horizontal between baseline and half-court)
        for (DetectedLine *line in horizontals) {
            if (line.lineType == CourtLineTypeOther) {
                // Could be free throw line if it's shorter and in the middle area
                CGFloat y = (line.startPoint.y + line.endPoint.y) / 2;
                if (y > 0.3 && y < 0.7 && line.length < sortedByLength[0].length * 0.8) {
                    line.lineType = CourtLineTypeFreeThrowLine;
                }
            }
        }

        // Calculate court bounds
        CGFloat minX = 1.0, maxX = 0.0, minY = 1.0, maxY = 0.0;
        for (DetectedLine *line in horizontals) {
            minX = MIN(minX, MIN(line.startPoint.x, line.endPoint.x));
            maxX = MAX(maxX, MAX(line.startPoint.x, line.endPoint.x));
            minY = MIN(minY, MIN(line.startPoint.y, line.endPoint.y));
            maxY = MAX(maxY, MAX(line.startPoint.y, line.endPoint.y));
        }
        for (DetectedLine *line in verticals) {
            minX = MIN(minX, MIN(line.startPoint.x, line.endPoint.x));
            maxX = MAX(maxX, MAX(line.startPoint.x, line.endPoint.x));
            minY = MIN(minY, MIN(line.startPoint.y, line.endPoint.y));
            maxY = MAX(maxY, MAX(line.startPoint.y, line.endPoint.y));
        }

        court.courtBounds = CGRectMake(minX, minY, maxX - minX, maxY - minY);
        court.isCourtDetected = YES;
    }

    court.horizontalLines = horizontals;
    court.verticalLines = verticals;
    court.arcLines = others;

    return court;
}

@end
