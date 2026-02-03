//
//  ShootingDetector.m
//  demoForNavigation1
//
//  Basketball shooting action detection using Vision framework
//

#import "ShootingDetector.h"

@interface ShootingDetector ()

@property (nonatomic, assign) NSInteger shotCount;
@property (nonatomic, assign) BOOL isDetecting;
@property (nonatomic, assign) ShootingPhase currentPhase;

// Tracking state
@property (nonatomic, assign) CGFloat peakWristHeight;
@property (nonatomic, assign) CGFloat lastWristY;
@property (nonatomic, assign) CGFloat lastElbowY;
@property (nonatomic, assign) CGFloat lastShoulderY;
@property (nonatomic, assign) BOOL armWasRaised;
@property (nonatomic, assign) NSInteger frameCount;
@property (nonatomic, strong) NSDate *lastShotTime;

// Vision request
@property (nonatomic, strong) VNDetectHumanBodyPoseRequest *poseRequest API_AVAILABLE(ios(14.0));

@end

@implementation ShootingDetector

- (instancetype)init {
    self = [super init];
    if (self) {
        _shotCount = 0;
        _isDetecting = NO;
        _currentPhase = ShootingPhaseIdle;
        _peakWristHeight = 0;
        _lastWristY = -1;
        _lastElbowY = -1;
        _lastShoulderY = -1;
        _armWasRaised = NO;
        _frameCount = 0;

        // Default sensitivity settings
        _raiseThreshold = 0.15;       // Wrist must be 15% above shoulder
        _releaseThreshold = 0.1;      // Extension detection threshold
        _confidenceThreshold = 0.3;   // Minimum pose confidence

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
    self.currentPhase = ShootingPhaseIdle;
    self.armWasRaised = NO;
    self.peakWristHeight = 0;
}

- (void)stopDetection {
    self.isDetecting = NO;
}

- (void)resetShotCount {
    self.shotCount = 0;
    self.currentPhase = ShootingPhaseIdle;
    self.armWasRaised = NO;
    self.peakWristHeight = 0;
    self.lastWristY = -1;
    self.lastElbowY = -1;
    self.lastShoulderY = -1;
    self.lastShotTime = nil;
}

- (void)processPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!self.isDetecting) {
        return;
    }

    // Process every 2nd frame for performance
    self.frameCount++;
    if (self.frameCount % 2 != 0) {
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

    NSError *error = nil;

    // Get right arm joints (typically the shooting arm)
    VNRecognizedPoint *rightWrist = [observation recognizedPointForJointName:VNHumanBodyPoseObservationJointNameRightWrist error:&error];
    VNRecognizedPoint *rightElbow = [observation recognizedPointForJointName:VNHumanBodyPoseObservationJointNameRightElbow error:&error];
    VNRecognizedPoint *rightShoulder = [observation recognizedPointForJointName:VNHumanBodyPoseObservationJointNameRightShoulder error:&error];

    // Get left arm joints as backup
    VNRecognizedPoint *leftWrist = [observation recognizedPointForJointName:VNHumanBodyPoseObservationJointNameLeftWrist error:&error];
    VNRecognizedPoint *leftElbow = [observation recognizedPointForJointName:VNHumanBodyPoseObservationJointNameLeftElbow error:&error];
    VNRecognizedPoint *leftShoulder = [observation recognizedPointForJointName:VNHumanBodyPoseObservationJointNameLeftShoulder error:&error];

    // Use the arm with higher wrist position (likely the shooting arm)
    VNRecognizedPoint *wrist = rightWrist;
    VNRecognizedPoint *elbow = rightElbow;
    VNRecognizedPoint *shoulder = rightShoulder;

    if (leftWrist.location.y > rightWrist.location.y && leftWrist.confidence > self.confidenceThreshold) {
        wrist = leftWrist;
        elbow = leftElbow;
        shoulder = leftShoulder;
    }

    // Check confidence
    CGFloat avgConfidence = (wrist.confidence + elbow.confidence + shoulder.confidence) / 3.0;
    if (avgConfidence < self.confidenceThreshold) {
        return;
    }

    // Notify delegate with pose data
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(poseUpdatedWithRightWrist:rightElbow:rightShoulder:confidence:)]) {
            [self.delegate poseUpdatedWithRightWrist:wrist.location
                                         rightElbow:elbow.location
                                       rightShoulder:shoulder.location
                                          confidence:avgConfidence];
        }
    });

    // Analyze shooting motion
    [self analyzeShootingMotion:wrist.location.y
                        elbowY:elbow.location.y
                     shoulderY:shoulder.location.y];
}

- (void)analyzeShootingMotion:(CGFloat)wristY elbowY:(CGFloat)elbowY shoulderY:(CGFloat)shoulderY {
    // In Vision coordinates, Y increases upward
    // Calculate relative positions
    CGFloat wristAboveShoulder = wristY - shoulderY;
    CGFloat elbowAboveShoulder = elbowY - shoulderY;

    // Initialize on first valid reading
    if (self.lastWristY < 0) {
        self.lastWristY = wristY;
        self.lastElbowY = elbowY;
        self.lastShoulderY = shoulderY;
        return;
    }

    // Track movement direction
    CGFloat wristDeltaY = wristY - self.lastWristY;
    BOOL wristMovingUp = wristDeltaY > 0.005;
    BOOL wristMovingDown = wristDeltaY < -0.005;

    // Update peak wrist height
    if (wristY > self.peakWristHeight) {
        self.peakWristHeight = wristY;
    }

    // State machine for shooting detection
    ShootingPhase previousPhase = self.currentPhase;

    switch (self.currentPhase) {
        case ShootingPhaseIdle:
            // Check if arm is being raised (wrist moving up and above shoulder)
            if (wristMovingUp && wristAboveShoulder > 0.05) {
                self.currentPhase = ShootingPhaseReady;
                self.peakWristHeight = wristY;
            }
            break;

        case ShootingPhaseReady:
            // Check if continuing to raise
            if (wristMovingUp && wristAboveShoulder > self.raiseThreshold) {
                self.currentPhase = ShootingPhaseRaising;
            } else if (wristAboveShoulder < 0) {
                // Arm lowered, reset
                self.currentPhase = ShootingPhaseIdle;
            }
            break;

        case ShootingPhaseRaising:
            // Track peak and wait for release
            if (wristMovingDown && (self.peakWristHeight - wristY) > self.releaseThreshold) {
                // Wrist started to come down after reaching peak = release!
                self.currentPhase = ShootingPhaseRelease;
                self.armWasRaised = YES;
            } else if (wristAboveShoulder < 0) {
                // Arm lowered without proper release, reset
                self.currentPhase = ShootingPhaseIdle;
                self.peakWristHeight = 0;
            }
            break;

        case ShootingPhaseRelease:
            // Confirm the shot and move to follow-through
            [self registerShot];
            self.currentPhase = ShootingPhaseFollowThrough;
            break;

        case ShootingPhaseFollowThrough:
            // Wait for arm to lower before detecting next shot
            if (wristAboveShoulder < 0.05) {
                self.currentPhase = ShootingPhaseIdle;
                self.armWasRaised = NO;
                self.peakWristHeight = 0;
            }
            break;
    }

    // Notify delegate of phase change
    if (previousPhase != self.currentPhase) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(shootingPhaseChanged:)]) {
                [self.delegate shootingPhaseChanged:self.currentPhase];
            }
        });
    }

    // Update last positions
    self.lastWristY = wristY;
    self.lastElbowY = elbowY;
    self.lastShoulderY = shoulderY;
}

- (void)registerShot {
    // Debounce: minimum 1 second between shots
    NSDate *now = [NSDate date];
    if (self.lastShotTime != nil) {
        NSTimeInterval timeSinceLastShot = [now timeIntervalSinceDate:self.lastShotTime];
        if (timeSinceLastShot < 1.0) {
            return;
        }
    }

    self.lastShotTime = now;
    self.shotCount++;

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(shootingDetected:)]) {
            [self.delegate shootingDetected:self.shotCount];
        }
    });
}

@end
