//
//  BallBouncingDetector.m
//  demoForNavigation1
//
//  Ball bouncing action detection using Vision framework
//

#import "BallBouncingDetector.h"

@interface BallBouncingDetector ()

@property (nonatomic, assign) NSInteger bounceCount;
@property (nonatomic, assign) BOOL isDetecting;

// Tracking state
@property (nonatomic, assign) CGFloat lastWristY;
@property (nonatomic, assign) CGFloat peakWristY;
@property (nonatomic, assign) CGFloat valleyWristY;
@property (nonatomic, assign) BOOL isMovingDown;
@property (nonatomic, assign) BOOL wasMovingDown;
@property (nonatomic, strong) NSDate *lastBounceTime;
@property (nonatomic, assign) NSInteger frameCount;

// Vision request
@property (nonatomic, strong) VNDetectHumanBodyPoseRequest *poseRequest API_AVAILABLE(ios(14.0));

@end

@implementation BallBouncingDetector

- (instancetype)init {
    self = [super init];
    if (self) {
        _bounceCount = 0;
        _isDetecting = NO;
        _lastWristY = -1;
        _peakWristY = -1;
        _valleyWristY = -1;
        _isMovingDown = NO;
        _wasMovingDown = NO;
        _frameCount = 0;

        // Default sensitivity settings
        _movementThreshold = 0.03;  // 3% of screen height
        _bounceTimeWindow = 2.0;    // 2 seconds max between bounces

        [self setupVisionRequest];
    }
    return self;
}

- (void)setupVisionRequest {
    if (@available(iOS 14.0, *)) {
        self.poseRequest = [[VNDetectHumanBodyPoseRequest alloc] init];
    }
}

- (void)startDetection {
    self.isDetecting = YES;
    self.frameCount = 0;
}

- (void)stopDetection {
    self.isDetecting = NO;
}

- (void)resetBounceCount {
    self.bounceCount = 0;
    self.lastWristY = -1;
    self.peakWristY = -1;
    self.valleyWristY = -1;
    self.isMovingDown = NO;
    self.wasMovingDown = NO;
    self.lastBounceTime = nil;
}

- (void)processPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!self.isDetecting) {
        return;
    }

    // Skip some frames for performance (process every 3rd frame)
    self.frameCount++;
    if (self.frameCount % 3 != 0) {
        return;
    }

    if (@available(iOS 14.0, *)) {
        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer options:@{}];

        NSError *error = nil;
        [handler performRequests:@[self.poseRequest] error:&error];

        if (error) {
            NSLog(@"Pose detection error: %@", error.localizedDescription);
            return;
        }

        [self processPoseResults:self.poseRequest.results];
    }
}

- (void)processPoseResults:(NSArray<VNHumanBodyPoseObservation *> *)results API_AVAILABLE(ios(14.0)) {
    if (results.count == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(personNotDetected)]) {
                [self.delegate personNotDetected];
            }
        });
        return;
    }

    VNHumanBodyPoseObservation *observation = results.firstObject;

    // Get right wrist point (primary hand for most people)
    NSError *error = nil;
    VNRecognizedPoint *rightWrist = [observation recognizedPointForJointName:VNHumanBodyPoseObservationJointNameRightWrist error:&error];
    VNRecognizedPoint *leftWrist = [observation recognizedPointForJointName:VNHumanBodyPoseObservationJointNameLeftWrist error:&error];

    // Use the wrist with higher confidence, or right wrist as default
    VNRecognizedPoint *wrist = rightWrist;
    if (leftWrist.confidence > rightWrist.confidence) {
        wrist = leftWrist;
    }

    if (wrist.confidence < 0.3) {
        return;  // Low confidence, skip this frame
    }

    CGFloat currentWristY = wrist.location.y;

    [self analyzeWristMovement:currentWristY];
}

- (void)analyzeWristMovement:(CGFloat)currentWristY {
    // Initialize on first valid reading
    if (self.lastWristY < 0) {
        self.lastWristY = currentWristY;
        self.peakWristY = currentWristY;
        self.valleyWristY = currentWristY;
        return;
    }

    CGFloat deltaY = currentWristY - self.lastWristY;

    // Determine movement direction (note: in Vision, Y increases upward)
    // Moving down = wrist Y decreasing (towards ground)
    BOOL currentlyMovingDown = deltaY < -0.005;  // Small threshold to filter noise
    BOOL currentlyMovingUp = deltaY > 0.005;

    // Track peaks and valleys
    if (currentlyMovingDown) {
        if (!self.isMovingDown && self.isDetecting) {
            // Direction changed from up to down - this is a peak
            self.peakWristY = self.lastWristY;
        }
        self.isMovingDown = YES;
    } else if (currentlyMovingUp) {
        if (self.isMovingDown && self.isDetecting) {
            // Direction changed from down to up - this is a valley (bounce point)
            self.valleyWristY = currentWristY;

            // Check if this is a valid bounce
            CGFloat bounceAmplitude = self.peakWristY - self.valleyWristY;

            if (bounceAmplitude > self.movementThreshold) {
                // Valid bounce detected!
                [self registerBounce];
            }
        }
        self.isMovingDown = NO;
    }

    self.lastWristY = currentWristY;

    // Notify delegate of position update
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(poseUpdatedWithWristY:isMovingDown:)]) {
            [self.delegate poseUpdatedWithWristY:currentWristY isMovingDown:self.isMovingDown];
        }
    });
}

- (void)registerBounce {
    NSDate *now = [NSDate date];

    // Check time window - bounces should happen within reasonable time
    if (self.lastBounceTime != nil) {
        NSTimeInterval timeSinceLastBounce = [now timeIntervalSinceDate:self.lastBounceTime];
        if (timeSinceLastBounce > self.bounceTimeWindow) {
            // Too long since last bounce, this might be a new sequence
            // Keep counting but note the gap
        }
    }

    self.lastBounceTime = now;
    self.bounceCount++;

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(ballBouncingDetected:)]) {
            [self.delegate ballBouncingDetected:self.bounceCount];
        }
    });
}

@end
