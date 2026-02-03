//
//  ShootingDetector.h
//  demoForNavigation1
//
//  Basketball shooting action detection using Vision framework
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ShootingPhase) {
    ShootingPhaseIdle,          // 空闲状态
    ShootingPhaseReady,         // 准备姿势 (手持球)
    ShootingPhaseRaising,       // 举球阶段
    ShootingPhaseRelease,       // 出手阶段
    ShootingPhaseFollowThrough  // 跟随阶段
};

@protocol ShootingDetectorDelegate <NSObject>

// Called when a complete shooting motion is detected
- (void)shootingDetected:(NSInteger)shotCount;

// Called when shooting phase changes
- (void)shootingPhaseChanged:(ShootingPhase)phase;

// Called with real-time pose data for visualization
- (void)poseUpdatedWithRightWrist:(CGPoint)rightWrist
                     rightElbow:(CGPoint)rightElbow
                   rightShoulder:(CGPoint)rightShoulder
                       confidence:(CGFloat)confidence;

// Called when no person is detected
- (void)personNotDetected;

@end

@interface ShootingDetector : NSObject

@property (nonatomic, weak) id<ShootingDetectorDelegate> delegate;
@property (nonatomic, readonly) NSInteger shotCount;
@property (nonatomic, readonly) BOOL isDetecting;
@property (nonatomic, readonly) ShootingPhase currentPhase;

// Detection sensitivity settings
@property (nonatomic, assign) CGFloat raiseThreshold;      // Minimum height to count as raised
@property (nonatomic, assign) CGFloat releaseThreshold;    // Extension threshold for release
@property (nonatomic, assign) CGFloat confidenceThreshold; // Minimum pose confidence

- (void)startDetection;
- (void)stopDetection;
- (void)resetShotCount;

// Process video frame for shooting detection
- (void)processPixelBuffer:(CVPixelBufferRef)pixelBuffer;

@end

NS_ASSUME_NONNULL_END
