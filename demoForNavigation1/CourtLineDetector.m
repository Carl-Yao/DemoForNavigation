//
//  CourtLineDetector.m
//  demoForNavigation1
//
//  Basketball court line detection using line detection + FIBA geometry validation
//
//  Strategy:
//  1. Use Vision contours to detect potential lines
//  2. Filter lines by straightness and length
//  3. Validate line relationships against FIBA court geometry
//  4. Find the best matching court configuration
//

#import "CourtLineDetector.h"
#import <Vision/Vision.h>

#pragma mark - Model Classes

@implementation CourtPose
- (instancetype)init {
    self = [super init];
    if (self) {
        _centerX = 0.5;
        _centerY = 0.5;
        _rotation = 0;
        _scale = 0.5;
        _perspectiveX = 0;
        _perspectiveY = 0;
        _matchScore = 0;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    CourtPose *copy = [[CourtPose alloc] init];
    copy.centerX = self.centerX;
    copy.centerY = self.centerY;
    copy.rotation = self.rotation;
    copy.scale = self.scale;
    copy.perspectiveX = self.perspectiveX;
    copy.perspectiveY = self.perspectiveY;
    copy.matchScore = self.matchScore;
    return copy;
}
@end

@implementation TemplateLine
+ (instancetype)lineFrom:(CGPoint)start to:(CGPoint)end name:(NSString *)name {
    TemplateLine *line = [[TemplateLine alloc] init];
    line.start = start;
    line.end = end;
    line.name = name;
    return line;
}
@end

@implementation ProjectedLine
@end

@implementation CourtDetectionResult
- (instancetype)init {
    self = [super init];
    if (self) {
        _projectedLines = @[];
        _courtFound = NO;
    }
    return self;
}
@end

#pragma mark - Detected Line Helper

@interface DetectedLine : NSObject
@property (nonatomic, assign) CGPoint start;
@property (nonatomic, assign) CGPoint end;
@property (nonatomic, assign) CGFloat length;
@property (nonatomic, assign) CGFloat angle;  // 0-180 degrees
@property (nonatomic, assign) BOOL isHorizontal;  // angle near 0 or 180
@property (nonatomic, assign) BOOL isVertical;    // angle near 90
@end

@implementation DetectedLine
@end

#pragma mark - CourtLineDetector

@interface CourtLineDetector ()

@property (nonatomic, assign) BOOL isDetecting;
@property (nonatomic, assign) NSInteger frameCount;
@property (nonatomic, strong) CIContext *ciContext;

// Detected lines from current frame
@property (nonatomic, strong) NSArray<DetectedLine *> *horizontalLines;
@property (nonatomic, strong) NSArray<DetectedLine *> *verticalLines;

// Best court match (for temporal smoothing)
@property (nonatomic, strong) NSArray<ProjectedLine *> *lastCourtLines;
@property (nonatomic, assign) CGFloat lastMatchScore;

@end

@implementation CourtLineDetector

- (instancetype)init {
    self = [super init];
    if (self) {
        _isDetecting = NO;
        _frameCount = 0;
        _edgeThreshold = 0.02;  // Contour threshold
        _minMatchScore = 0.3;
        _ciContext = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}];
        _horizontalLines = @[];
        _verticalLines = @[];
    }
    return self;
}

#pragma mark - Detection Control

- (void)startDetection {
    self.isDetecting = YES;
    self.frameCount = 0;
    self.lastCourtLines = nil;
    self.lastMatchScore = 0;
}

- (void)stopDetection {
    self.isDetecting = NO;
}

- (void)processPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!self.isDetecting) return;

    self.frameCount++;
    if (self.frameCount % 3 != 0) return;  // Process every 3rd frame

    [self detectCourtInPixelBuffer:pixelBuffer];
}

#pragma mark - Main Detection

- (void)detectCourtInPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    CIImage *inputImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    if (!inputImage) {
        [self reportError:@"Failed to create image"];
        return;
    }

    // Rotate for portrait display
    inputImage = [inputImage imageByApplyingCGOrientation:kCGImagePropertyOrientationRight];
    CGSize imageSize = inputImage.extent.size;

    // Step 1: Detect contours using Vision
    [self detectContoursInImage:inputImage imageSize:imageSize completion:^(NSArray<DetectedLine *> *lines) {
        if (lines.count == 0) {
            [self reportNoCourtFound];
            return;
        }

        // Step 2: Classify lines as horizontal or vertical
        [self classifyLines:lines];

        // Step 3: Find best court configuration
        CourtDetectionResult *result = [self findBestCourtConfiguration:imageSize];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate courtLineDetector:self didDetectResult:result];
        });
    }];
}

#pragma mark - Contour Detection

- (void)detectContoursInImage:(CIImage *)image imageSize:(CGSize)imageSize completion:(void(^)(NSArray<DetectedLine *> *))completion {

    // Preprocess: enhance contrast
    CIFilter *colorControls = [CIFilter filterWithName:@"CIColorControls"];
    [colorControls setValue:image forKey:kCIInputImageKey];
    [colorControls setValue:@1.5 forKey:kCIInputContrastKey];
    [colorControls setValue:@0 forKey:kCIInputSaturationKey];
    CIImage *processedImage = colorControls.outputImage;

    CGImageRef cgImage = [self.ciContext createCGImage:processedImage fromRect:processedImage.extent];
    if (!cgImage) {
        completion(@[]);
        return;
    }

    VNDetectContoursRequest *request = [[VNDetectContoursRequest alloc] initWithCompletionHandler:^(VNRequest *request, NSError *error) {
        CGImageRelease(cgImage);

        if (error) {
            completion(@[]);
            return;
        }

        NSMutableArray<DetectedLine *> *lines = [NSMutableArray array];

        for (VNContoursObservation *observation in request.results) {
            // Process top-level contours
            for (NSInteger i = 0; i < observation.topLevelContourCount; i++) {
                VNContour *contour = [observation topLevelContourAtIndex:i error:nil];
                if (!contour) continue;

                DetectedLine *line = [self extractLineFromContour:contour imageSize:imageSize];
                if (line) {
                    [lines addObject:line];
                }

                // Also check child contours
                for (NSInteger j = 0; j < contour.childContourCount; j++) {
                    VNContour *child = [contour childContourAtIndex:j error:nil];
                    if (!child) continue;

                    DetectedLine *childLine = [self extractLineFromContour:child imageSize:imageSize];
                    if (childLine) {
                        [lines addObject:childLine];
                    }
                }
            }
        }

        completion(lines);
    }];

    request.contrastAdjustment = self.edgeThreshold;
    request.detectsDarkOnLight = NO;

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cgImage options:@{}];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [handler performRequests:@[request] error:nil];
    });
}

- (DetectedLine *)extractLineFromContour:(VNContour *)contour imageSize:(CGSize)imageSize {
    NSInteger pointCount = contour.pointCount;
    if (pointCount < 2) return nil;

    // Get contour points
    const simd_float2 *points = contour.normalizedPoints;

    // Calculate bounding box and path length
    CGFloat minX = CGFLOAT_MAX, maxX = -CGFLOAT_MAX;
    CGFloat minY = CGFLOAT_MAX, maxY = -CGFLOAT_MAX;
    CGFloat pathLength = 0;

    for (NSInteger i = 0; i < pointCount; i++) {
        CGFloat x = points[i].x;
        CGFloat y = points[i].y;

        minX = MIN(minX, x);
        maxX = MAX(maxX, x);
        minY = MIN(minY, y);
        maxY = MAX(maxY, y);

        if (i > 0) {
            CGFloat dx = x - points[i-1].x;
            CGFloat dy = y - points[i-1].y;
            pathLength += sqrt(dx*dx + dy*dy);
        }
    }

    CGFloat width = maxX - minX;
    CGFloat height = maxY - minY;
    CGFloat directDistance = sqrt(width*width + height*height);

    // Filter: minimum length (at least 8% of image dimension)
    CGFloat minLength = 0.08;
    if (directDistance < minLength) return nil;

    // Filter: straightness (direct distance / path length > 85%)
    CGFloat straightness = pathLength > 0 ? directDistance / pathLength : 0;
    if (straightness < 0.85) return nil;

    // Calculate line endpoints and angle
    CGPoint start = CGPointMake(points[0].x, points[0].y);
    CGPoint end = CGPointMake(points[pointCount-1].x, points[pointCount-1].y);

    CGFloat dx = end.x - start.x;
    CGFloat dy = end.y - start.y;
    CGFloat angle = atan2(dy, dx) * 180.0 / M_PI;
    if (angle < 0) angle += 180;  // Normalize to 0-180

    // Create detected line
    DetectedLine *line = [[DetectedLine alloc] init];
    line.start = start;
    line.end = end;
    line.length = directDistance;
    line.angle = angle;

    // Classify: horizontal (0-25° or 155-180°) or vertical (65-115°)
    line.isHorizontal = (angle <= 25) || (angle >= 155);
    line.isVertical = (angle >= 65) && (angle <= 115);

    return line;
}

#pragma mark - Line Classification

- (void)classifyLines:(NSArray<DetectedLine *> *)lines {
    NSMutableArray *horizontal = [NSMutableArray array];
    NSMutableArray *vertical = [NSMutableArray array];

    for (DetectedLine *line in lines) {
        if (line.isHorizontal) {
            [horizontal addObject:line];
        } else if (line.isVertical) {
            [vertical addObject:line];
        }
    }

    // Sort by length (longest first)
    [horizontal sortUsingComparator:^NSComparisonResult(DetectedLine *a, DetectedLine *b) {
        return [@(b.length) compare:@(a.length)];
    }];
    [vertical sortUsingComparator:^NSComparisonResult(DetectedLine *a, DetectedLine *b) {
        return [@(b.length) compare:@(a.length)];
    }];

    self.horizontalLines = horizontal;
    self.verticalLines = vertical;
}

#pragma mark - Court Configuration Finding

- (CourtDetectionResult *)findBestCourtConfiguration:(CGSize)imageSize {
    CourtDetectionResult *result = [[CourtDetectionResult alloc] init];
    result.courtFound = NO;

    NSMutableArray<ProjectedLine *> *courtLines = [NSMutableArray array];
    CGFloat matchScore = 0;
    NSInteger matchedLines = 0;

    // Need at least some horizontal and vertical lines
    if (self.horizontalLines.count < 1 || self.verticalLines.count < 1) {
        // Just show detected lines without validation
        for (DetectedLine *line in self.horizontalLines) {
            ProjectedLine *pl = [[ProjectedLine alloc] init];
            pl.start = line.start;
            pl.end = line.end;
            pl.name = @"horizontal";
            pl.isVisible = YES;
            [courtLines addObject:pl];
        }
        for (DetectedLine *line in self.verticalLines) {
            ProjectedLine *pl = [[ProjectedLine alloc] init];
            pl.start = line.start;
            pl.end = line.end;
            pl.name = @"vertical";
            pl.isVisible = YES;
            [courtLines addObject:pl];
        }
        result.projectedLines = courtLines;
        return result;
    }

    // FIBA half-court aspect ratio: 15m / 14m ≈ 1.07 (width / height)
    // On phone held portrait, court appears wider than tall
    CGFloat fibaAspect = 15.0 / 14.0;
    CGFloat aspectTolerance = 0.4;  // Allow some perspective distortion

    // Try to find a rectangular court region
    // Look for two roughly parallel horizontal lines (baseline + free-throw or mid-court)
    // and two roughly parallel vertical lines (sidelines)

    DetectedLine *bestTop = nil;
    DetectedLine *bestBottom = nil;
    DetectedLine *bestLeft = nil;
    DetectedLine *bestRight = nil;
    CGFloat bestRectScore = 0;

    // Try combinations of horizontal lines (limit to top 5)
    NSInteger hLimit = MIN(5, self.horizontalLines.count);
    NSInteger vLimit = MIN(5, self.verticalLines.count);

    for (NSInteger i = 0; i < hLimit; i++) {
        for (NSInteger j = i + 1; j < hLimit; j++) {
            DetectedLine *h1 = self.horizontalLines[i];
            DetectedLine *h2 = self.horizontalLines[j];

            // Check if roughly parallel (angle difference < 15°)
            CGFloat angleDiff = fabs(h1.angle - h2.angle);
            if (angleDiff > 15 && angleDiff < 165) continue;

            // Determine which is top/bottom based on Y position
            CGFloat y1 = (h1.start.y + h1.end.y) / 2;
            CGFloat y2 = (h2.start.y + h2.end.y) / 2;
            DetectedLine *top = (y1 > y2) ? h1 : h2;
            DetectedLine *bottom = (y1 > y2) ? h2 : h1;

            CGFloat courtHeight = fabs(y1 - y2);
            if (courtHeight < 0.1) continue;  // Too small

            // Try combinations of vertical lines
            for (NSInteger k = 0; k < vLimit; k++) {
                for (NSInteger l = k + 1; l < vLimit; l++) {
                    DetectedLine *v1 = self.verticalLines[k];
                    DetectedLine *v2 = self.verticalLines[l];

                    // Check parallel
                    CGFloat vAngleDiff = fabs(v1.angle - v2.angle);
                    if (vAngleDiff > 15 && vAngleDiff < 165) continue;

                    // Determine left/right
                    CGFloat x1 = (v1.start.x + v1.end.x) / 2;
                    CGFloat x2 = (v2.start.x + v2.end.x) / 2;
                    DetectedLine *left = (x1 < x2) ? v1 : v2;
                    DetectedLine *right = (x1 < x2) ? v2 : v1;

                    CGFloat courtWidth = fabs(x1 - x2);
                    if (courtWidth < 0.1) continue;  // Too small

                    // Check aspect ratio
                    CGFloat aspect = courtWidth / courtHeight;
                    if (fabs(aspect - fibaAspect) > aspectTolerance) continue;

                    // Check minimum area (at least 10% of screen)
                    CGFloat area = courtWidth * courtHeight;
                    if (area < 0.10) continue;

                    // Score this configuration
                    CGFloat score = (top.length + bottom.length + left.length + right.length) / 4.0;
                    score *= (1.0 - fabs(aspect - fibaAspect) / aspectTolerance);  // Prefer closer to FIBA aspect
                    score *= area;  // Prefer larger courts

                    if (score > bestRectScore) {
                        bestRectScore = score;
                        bestTop = top;
                        bestBottom = bottom;
                        bestLeft = left;
                        bestRight = right;
                    }
                }
            }
        }
    }

    // Build court lines from best match
    if (bestRectScore > 0) {
        // Add the four boundary lines
        [self addLine:bestTop name:@"baseline" toArray:courtLines];
        [self addLine:bestBottom name:@"midcourt" toArray:courtLines];
        [self addLine:bestLeft name:@"sideline_left" toArray:courtLines];
        [self addLine:bestRight name:@"sideline_right" toArray:courtLines];
        matchedLines = 4;

        // Calculate court bounds for finding interior lines
        CGFloat courtLeft = MIN((bestLeft.start.x + bestLeft.end.x) / 2, (bestRight.start.x + bestRight.end.x) / 2);
        CGFloat courtRight = MAX((bestLeft.start.x + bestLeft.end.x) / 2, (bestRight.start.x + bestRight.end.x) / 2);
        CGFloat courtTop = MAX((bestTop.start.y + bestTop.end.y) / 2, (bestBottom.start.y + bestBottom.end.y) / 2);
        CGFloat courtBottom = MIN((bestTop.start.y + bestTop.end.y) / 2, (bestBottom.start.y + bestBottom.end.y) / 2);
        CGFloat courtWidth = courtRight - courtLeft;
        CGFloat courtHeight = courtTop - courtBottom;

        // Look for free-throw line (horizontal, inside court, at ~41% from baseline)
        CGFloat freeThrowExpectedY = courtBottom + courtHeight * 0.414;  // 5.8m / 14m
        for (DetectedLine *h in self.horizontalLines) {
            if (h == bestTop || h == bestBottom) continue;

            CGFloat y = (h.start.y + h.end.y) / 2;
            CGFloat x = (h.start.x + h.end.x) / 2;

            // Check if inside court horizontally
            if (x < courtLeft || x > courtRight) continue;

            // Check if at expected Y position (±10% of court height)
            if (fabs(y - freeThrowExpectedY) < courtHeight * 0.15) {
                [self addLine:h name:@"freethrow" toArray:courtLines];
                matchedLines++;
                break;
            }
        }

        // Look for lane lines (vertical, inside court, symmetric)
        CGFloat laneExpectedX = courtWidth * 0.163;  // (4.9m / 2) / 15m
        for (DetectedLine *v in self.verticalLines) {
            if (v == bestLeft || v == bestRight) continue;

            CGFloat x = (v.start.x + v.end.x) / 2;
            CGFloat y = (v.start.y + v.end.y) / 2;

            // Check if inside court
            if (y < courtBottom || y > courtTop) continue;

            // Check if at expected X position (lane line)
            CGFloat distFromCenter = fabs(x - (courtLeft + courtWidth / 2));
            if (fabs(distFromCenter - laneExpectedX) < courtWidth * 0.1) {
                [self addLine:v name:@"lane" toArray:courtLines];
                matchedLines++;
            }
        }

        matchScore = (CGFloat)matchedLines / 6.0;  // 6 expected lines for half court
        result.courtFound = matchScore >= 0.5;  // At least 3 lines matched
    } else {
        // No valid rectangle found, just show all detected lines
        for (DetectedLine *line in self.horizontalLines) {
            [self addLine:line name:@"horizontal" toArray:courtLines];
        }
        for (DetectedLine *line in self.verticalLines) {
            [self addLine:line name:@"vertical" toArray:courtLines];
        }
    }

    // Create pose info for display
    CourtPose *pose = [[CourtPose alloc] init];
    pose.matchScore = matchScore;
    if (bestTop && bestBottom && bestLeft && bestRight) {
        pose.centerX = ((bestLeft.start.x + bestLeft.end.x) / 2 + (bestRight.start.x + bestRight.end.x) / 2) / 2;
        pose.centerY = ((bestTop.start.y + bestTop.end.y) / 2 + (bestBottom.start.y + bestBottom.end.y) / 2) / 2;
    }

    result.bestPose = pose;
    result.projectedLines = courtLines;

    return result;
}

- (void)addLine:(DetectedLine *)line name:(NSString *)name toArray:(NSMutableArray<ProjectedLine *> *)array {
    ProjectedLine *pl = [[ProjectedLine alloc] init];
    pl.start = line.start;
    pl.end = line.end;
    pl.name = name;
    pl.isVisible = YES;
    [array addObject:pl];
}

#pragma mark - Helpers

- (void)reportNoCourtFound {
    CourtDetectionResult *result = [[CourtDetectionResult alloc] init];
    result.courtFound = NO;
    result.projectedLines = @[];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate courtLineDetector:self didDetectResult:result];
    });
}

- (void)reportError:(NSString *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate courtLineDetectorDidFail:self withError:error];
    });
}

@end
