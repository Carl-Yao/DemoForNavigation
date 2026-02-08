//
//  CourtLineDetector.m
//  demoForNavigation1
//
//  Basketball court line detection using FIBA template matching
//
//  FIBA Half-Court Dimensions (meters):
//  - Court: 15m (width) x 14m (length from baseline to half-court)
//  - Free throw line: 5.8m from baseline
//  - Free throw lane: 4.9m wide
//  - Three-point arc: 6.75m radius
//  - Restricted area arc: 1.25m radius
//

#import "CourtLineDetector.h"

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

#pragma mark - CourtLineDetector

@interface CourtLineDetector ()

@property (nonatomic, assign) BOOL isDetecting;
@property (nonatomic, assign) NSInteger frameCount;
@property (nonatomic, strong) NSArray<TemplateLine *> *courtTemplate;
@property (nonatomic, strong) CIContext *ciContext;
@property (nonatomic, strong) CourtPose *lastBestPose;  // For temporal smoothing

@end

@implementation CourtLineDetector

- (instancetype)init {
    self = [super init];
    if (self) {
        _isDetecting = NO;
        _frameCount = 0;
        _edgeThreshold = 1.5;
        _minMatchScore = 0.15;
        _ciContext = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}];
        [self buildCourtTemplate];
    }
    return self;
}

#pragma mark - FIBA Court Template

- (void)buildCourtTemplate {
    // FIBA half-court normalized to (-0.5, -0.5) to (0.5, 0.5)
    // Aspect ratio: 15m / 14m ≈ 1.07
    // We normalize width to 1.0, so height = 14/15 ≈ 0.933

    CGFloat halfWidth = 0.5;
    CGFloat halfHeight = 0.5 * (14.0 / 15.0);  // Maintain aspect ratio

    // Free throw line: 5.8m from baseline = 5.8/14 ≈ 0.414 of length
    CGFloat freeThrowY = -halfHeight + (halfHeight * 2) * (5.8 / 14.0);

    // Free throw lane: 4.9m wide = 4.9/15 ≈ 0.327 of width
    CGFloat laneHalfWidth = halfWidth * (4.9 / 15.0) / 2.0;

    NSMutableArray *lines = [NSMutableArray array];

    // Baseline (bottom)
    [lines addObject:[TemplateLine lineFrom:CGPointMake(-halfWidth, -halfHeight)
                                         to:CGPointMake(halfWidth, -halfHeight)
                                       name:@"baseline"]];

    // Half-court line (top)
    [lines addObject:[TemplateLine lineFrom:CGPointMake(-halfWidth, halfHeight)
                                         to:CGPointMake(halfWidth, halfHeight)
                                       name:@"halfcourt"]];

    // Left sideline
    [lines addObject:[TemplateLine lineFrom:CGPointMake(-halfWidth, -halfHeight)
                                         to:CGPointMake(-halfWidth, halfHeight)
                                       name:@"sideline_left"]];

    // Right sideline
    [lines addObject:[TemplateLine lineFrom:CGPointMake(halfWidth, -halfHeight)
                                         to:CGPointMake(halfWidth, halfHeight)
                                       name:@"sideline_right"]];

    // Free throw line
    [lines addObject:[TemplateLine lineFrom:CGPointMake(-laneHalfWidth, freeThrowY)
                                         to:CGPointMake(laneHalfWidth, freeThrowY)
                                       name:@"freethrow"]];

    // Left lane line
    [lines addObject:[TemplateLine lineFrom:CGPointMake(-laneHalfWidth, -halfHeight)
                                         to:CGPointMake(-laneHalfWidth, freeThrowY)
                                       name:@"lane_left"]];

    // Right lane line
    [lines addObject:[TemplateLine lineFrom:CGPointMake(laneHalfWidth, -halfHeight)
                                         to:CGPointMake(laneHalfWidth, freeThrowY)
                                       name:@"lane_right"]];

    // Three-point arc (approximated with line segments)
    // 6.75m radius, but corners are straight at 0.9m from sideline
    CGFloat threePointRadius = 6.75 / 15.0;  // Normalized
    CGFloat cornerDistance = 0.9 / 15.0;     // Corner three distance from sideline

    // Left corner three
    [lines addObject:[TemplateLine lineFrom:CGPointMake(-halfWidth + cornerDistance, -halfHeight)
                                         to:CGPointMake(-halfWidth + cornerDistance, -halfHeight + 0.15)
                                       name:@"three_corner_left"]];

    // Right corner three
    [lines addObject:[TemplateLine lineFrom:CGPointMake(halfWidth - cornerDistance, -halfHeight)
                                         to:CGPointMake(halfWidth - cornerDistance, -halfHeight + 0.15)
                                       name:@"three_corner_right"]];

    // Arc segments (simplified)
    NSInteger arcSegments = 8;
    CGFloat arcStartAngle = M_PI * 0.15;  // Start angle
    CGFloat arcEndAngle = M_PI * 0.85;    // End angle
    CGFloat basketY = -halfHeight + 1.575 / 14.0;  // Basket is 1.575m from baseline

    for (NSInteger i = 0; i < arcSegments; i++) {
        CGFloat angle1 = arcStartAngle + (arcEndAngle - arcStartAngle) * i / arcSegments;
        CGFloat angle2 = arcStartAngle + (arcEndAngle - arcStartAngle) * (i + 1) / arcSegments;

        CGPoint p1 = CGPointMake(cos(angle1) * threePointRadius, basketY + sin(angle1) * threePointRadius);
        CGPoint p2 = CGPointMake(cos(angle2) * threePointRadius, basketY + sin(angle2) * threePointRadius);

        [lines addObject:[TemplateLine lineFrom:p1 to:p2 name:@"three_arc"]];
    }

    self.courtTemplate = lines;
}

#pragma mark - Detection Control

- (void)startDetection {
    self.isDetecting = YES;
    self.frameCount = 0;
    self.lastBestPose = nil;
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
    // Create edge image
    CIImage *inputImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    if (!inputImage) {
        [self reportError:@"Failed to create image"];
        return;
    }

    // Rotate for portrait display
    inputImage = [inputImage imageByApplyingCGOrientation:kCGImagePropertyOrientationRight];
    CGRect extent = inputImage.extent;

    // Create edge-detected image
    CIImage *edgeImage = [self createEdgeImage:inputImage];
    if (!edgeImage) {
        [self reportError:@"Edge detection failed"];
        return;
    }

    // Sample edge image into a buffer for fast access
    NSData *edgeData = [self sampleEdgeImage:edgeImage extent:extent];
    if (!edgeData) {
        [self reportError:@"Failed to sample edges"];
        return;
    }

    NSInteger sampleWidth = 128;
    NSInteger sampleHeight = 128;

    // Find best matching pose using coarse-to-fine search
    CourtPose *bestPose = [self findBestPose:edgeData
                                sampleWidth:sampleWidth
                               sampleHeight:sampleHeight];

    // Apply temporal smoothing
    if (self.lastBestPose && bestPose.matchScore > self.minMatchScore) {
        bestPose = [self smoothPose:bestPose withPrevious:self.lastBestPose];
    }
    self.lastBestPose = bestPose;

    // Project template with best pose
    NSArray<ProjectedLine *> *projectedLines = [self projectTemplateWithPose:bestPose];

    // Create result
    CourtDetectionResult *result = [[CourtDetectionResult alloc] init];
    result.bestPose = bestPose;
    result.projectedLines = projectedLines;
    result.courtFound = bestPose.matchScore >= self.minMatchScore;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate courtLineDetector:self didDetectResult:result];
    });
}

#pragma mark - Edge Detection

- (CIImage *)createEdgeImage:(CIImage *)inputImage {
    // Grayscale
    CIFilter *gray = [CIFilter filterWithName:@"CIColorControls"];
    [gray setValue:inputImage forKey:kCIInputImageKey];
    [gray setValue:@0 forKey:kCIInputSaturationKey];
    [gray setValue:@1.3 forKey:kCIInputContrastKey];

    // Edge detection
    CIFilter *edges = [CIFilter filterWithName:@"CIEdges"];
    [edges setValue:gray.outputImage forKey:kCIInputImageKey];
    [edges setValue:@(self.edgeThreshold) forKey:kCIInputIntensityKey];

    return edges.outputImage;
}

- (NSData *)sampleEdgeImage:(CIImage *)edgeImage extent:(CGRect)extent {
    NSInteger sampleWidth = 128;
    NSInteger sampleHeight = 128;

    // Render edge image to a small bitmap for fast sampling
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
    NSMutableData *data = [NSMutableData dataWithLength:sampleWidth * sampleHeight];

    CGContextRef context = CGBitmapContextCreate(data.mutableBytes,
                                                  sampleWidth, sampleHeight,
                                                  8, sampleWidth,
                                                  colorSpace, kCGImageAlphaNone);
    CGColorSpaceRelease(colorSpace);

    if (!context) return nil;

    // Scale and render
    CGContextScaleCTM(context, sampleWidth / extent.size.width, sampleHeight / extent.size.height);

    CGImageRef cgImage = [self.ciContext createCGImage:edgeImage fromRect:extent];
    if (cgImage) {
        CGContextDrawImage(context, extent, cgImage);
        CGImageRelease(cgImage);
    }

    CGContextRelease(context);

    return data;
}

#pragma mark - Pose Search

- (CourtPose *)findBestPose:(NSData *)edgeData
                sampleWidth:(NSInteger)sampleWidth
               sampleHeight:(NSInteger)sampleHeight {

    CourtPose *bestPose = [[CourtPose alloc] init];
    bestPose.scale = 0.4;  // Default to reasonable size
    CGFloat bestScore = 0;

    const uint8_t *pixels = edgeData.bytes;

    // Constraint 1: Only search reasonable rotations (0°, 90°, 180°, 270° ±15°)
    // Basketball courts are rectangular, so only these rotations make sense
    CGFloat validRotations[] = {0, 90, 180, 270};
    NSInteger rotationCount = 4;

    // Constraint 2: Minimum scale 0.35 ensures court is at least ~10% of screen area
    // (0.35 * 0.35 ≈ 0.12 = 12% area coverage)
    CGFloat minScale = 0.35;
    CGFloat maxScale = 0.9;

    // Constraint 3: Perspective limited to realistic camera angles
    CGFloat maxPerspective = 0.25;

    // Coarse search with constraints
    for (NSInteger ri = 0; ri < rotationCount; ri++) {
        CGFloat baseRotation = validRotations[ri];

        for (CGFloat rotOffset = -15; rotOffset <= 15; rotOffset += 15) {
            CGFloat rotation = baseRotation + rotOffset;

            for (CGFloat scale = minScale; scale <= maxScale; scale += 0.12) {
                for (CGFloat cx = 0.2; cx <= 0.8; cx += 0.12) {
                    for (CGFloat cy = 0.15; cy <= 0.85; cy += 0.12) {
                        for (CGFloat perspY = -maxPerspective; perspY <= maxPerspective; perspY += 0.12) {

                            CourtPose *pose = [[CourtPose alloc] init];
                            pose.centerX = cx;
                            pose.centerY = cy;
                            pose.rotation = rotation;
                            pose.scale = scale;
                            pose.perspectiveY = perspY;

                            CGFloat score = [self scorePose:pose
                                                     pixels:pixels
                                                      width:sampleWidth
                                                     height:sampleHeight];

                            if (score > bestScore) {
                                bestScore = score;
                                bestPose = [pose copy];
                                bestPose.matchScore = score;
                            }
                        }
                    }
                }
            }
        }
    }

    // Fine search around best pose
    if (bestScore > 0.05) {
        bestPose = [self refinePose:bestPose
                             pixels:pixels
                              width:sampleWidth
                             height:sampleHeight
                           minScale:minScale];
    }

    return bestPose;
}

- (CourtPose *)refinePose:(CourtPose *)initialPose
                   pixels:(const uint8_t *)pixels
                    width:(NSInteger)width
                   height:(NSInteger)height
                 minScale:(CGFloat)minScale {

    CourtPose *bestPose = [initialPose copy];
    CGFloat bestScore = initialPose.matchScore;

    // Fine search with smaller steps, but respect constraints
    CGFloat rotationRange = 12;  // Only ±12° fine adjustment
    CGFloat scaleRange = 0.08;
    CGFloat posRange = 0.08;
    CGFloat perspRange = 0.1;
    CGFloat maxPerspective = 0.25;

    for (CGFloat dr = -rotationRange; dr <= rotationRange; dr += 3) {
        for (CGFloat ds = -scaleRange; ds <= scaleRange; ds += 0.02) {
            CGFloat newScale = initialPose.scale + ds;
            if (newScale < minScale) continue;  // Enforce minimum scale

            for (CGFloat dx = -posRange; dx <= posRange; dx += 0.02) {
                for (CGFloat dy = -posRange; dy <= posRange; dy += 0.02) {
                    for (CGFloat dpy = -perspRange; dpy <= perspRange; dpy += 0.04) {
                        CGFloat newPerspY = initialPose.perspectiveY + dpy;
                        if (fabs(newPerspY) > maxPerspective) continue;  // Enforce perspective limit

                        CourtPose *pose = [[CourtPose alloc] init];
                        pose.centerX = initialPose.centerX + dx;
                        pose.centerY = initialPose.centerY + dy;
                        pose.rotation = initialPose.rotation + dr;
                        pose.scale = newScale;
                        pose.perspectiveY = newPerspY;

                        CGFloat score = [self scorePose:pose pixels:pixels width:width height:height];

                        if (score > bestScore) {
                            bestScore = score;
                            bestPose = [pose copy];
                            bestPose.matchScore = score;
                        }
                    }
                }
            }
        }
    }

    return bestPose;
}

#pragma mark - Scoring

- (CGFloat)scorePose:(CourtPose *)pose
              pixels:(const uint8_t *)pixels
               width:(NSInteger)width
              height:(NSInteger)height {

    CGFloat totalScore = 0;
    NSInteger sampleCount = 0;

    CGFloat cosR = cos(pose.rotation * M_PI / 180.0);
    CGFloat sinR = sin(pose.rotation * M_PI / 180.0);

    for (TemplateLine *templateLine in self.courtTemplate) {
        // Transform template line to image coordinates
        CGPoint p1 = [self transformPoint:templateLine.start
                                 withPose:pose
                                     cosR:cosR sinR:sinR];
        CGPoint p2 = [self transformPoint:templateLine.end
                                 withPose:pose
                                     cosR:cosR sinR:sinR];

        // Sample along the line
        CGFloat lineLength = hypot(p2.x - p1.x, p2.y - p1.y);
        NSInteger samples = MAX(5, (NSInteger)(lineLength * width));

        for (NSInteger i = 0; i <= samples; i++) {
            CGFloat t = (CGFloat)i / samples;
            CGFloat x = p1.x + t * (p2.x - p1.x);
            CGFloat y = p1.y + t * (p2.y - p1.y);

            // Check bounds
            if (x < 0 || x >= 1 || y < 0 || y >= 1) continue;

            // Sample edge image
            NSInteger px = (NSInteger)(x * (width - 1));
            NSInteger py = (NSInteger)(y * (height - 1));
            NSInteger idx = py * width + px;

            CGFloat edgeValue = pixels[idx] / 255.0;
            totalScore += edgeValue;
            sampleCount++;
        }
    }

    return sampleCount > 0 ? totalScore / sampleCount : 0;
}

- (CGPoint)transformPoint:(CGPoint)point
                 withPose:(CourtPose *)pose
                     cosR:(CGFloat)cosR
                     sinR:(CGFloat)sinR {

    // Apply scale
    CGFloat x = point.x * pose.scale;
    CGFloat y = point.y * pose.scale;

    // Apply perspective (simple linear perspective)
    CGFloat perspFactor = 1.0 + point.y * pose.perspectiveY;
    x *= perspFactor;

    // Apply rotation
    CGFloat rx = x * cosR - y * sinR;
    CGFloat ry = x * sinR + y * cosR;

    // Apply translation (convert from -0.5..0.5 to 0..1)
    rx += pose.centerX;
    ry += pose.centerY;

    return CGPointMake(rx, ry);
}

#pragma mark - Projection

- (NSArray<ProjectedLine *> *)projectTemplateWithPose:(CourtPose *)pose {
    NSMutableArray *projected = [NSMutableArray array];

    CGFloat cosR = cos(pose.rotation * M_PI / 180.0);
    CGFloat sinR = sin(pose.rotation * M_PI / 180.0);

    for (TemplateLine *templateLine in self.courtTemplate) {
        ProjectedLine *line = [[ProjectedLine alloc] init];
        line.name = templateLine.name;

        line.start = [self transformPoint:templateLine.start withPose:pose cosR:cosR sinR:sinR];
        line.end = [self transformPoint:templateLine.end withPose:pose cosR:cosR sinR:sinR];

        // Check if line is visible
        line.isVisible = [self isLineVisible:line];

        [projected addObject:line];
    }

    return projected;
}

- (BOOL)isLineVisible:(ProjectedLine *)line {
    // Check if at least part of line is in view (0-1 range)
    CGFloat minX = MIN(line.start.x, line.end.x);
    CGFloat maxX = MAX(line.start.x, line.end.x);
    CGFloat minY = MIN(line.start.y, line.end.y);
    CGFloat maxY = MAX(line.start.y, line.end.y);

    return !(maxX < 0 || minX > 1 || maxY < 0 || minY > 1);
}

#pragma mark - Temporal Smoothing

- (CourtPose *)smoothPose:(CourtPose *)newPose withPrevious:(CourtPose *)prevPose {
    CGFloat alpha = 0.7;  // Smoothing factor (higher = more responsive)

    CourtPose *smoothed = [[CourtPose alloc] init];
    smoothed.centerX = alpha * newPose.centerX + (1 - alpha) * prevPose.centerX;
    smoothed.centerY = alpha * newPose.centerY + (1 - alpha) * prevPose.centerY;
    smoothed.scale = alpha * newPose.scale + (1 - alpha) * prevPose.scale;
    smoothed.perspectiveY = alpha * newPose.perspectiveY + (1 - alpha) * prevPose.perspectiveY;
    smoothed.matchScore = newPose.matchScore;

    // Handle rotation wrap-around
    CGFloat rotDiff = newPose.rotation - prevPose.rotation;
    if (rotDiff > 180) rotDiff -= 360;
    if (rotDiff < -180) rotDiff += 360;
    smoothed.rotation = prevPose.rotation + alpha * rotDiff;
    if (smoothed.rotation < 0) smoothed.rotation += 360;
    if (smoothed.rotation >= 360) smoothed.rotation -= 360;

    return smoothed;
}

#pragma mark - Error Handling

- (void)reportError:(NSString *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate courtLineDetectorDidFail:self withError:error];
    });
}

@end
