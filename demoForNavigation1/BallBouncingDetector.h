//
//  BallBouncingDetector.h
//  demoForNavigation1
//
//  Ball bouncing action detection using Vision framework
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>

NS_ASSUME_NONNULL_BEGIN

@protocol BallBouncingDetectorDelegate <NSObject>

// Called when ball bouncing action is detected
- (void)ballBouncingDetected:(NSInteger)bounceCount;

// Called when pose detection updates with wrist position
- (void)poseUpdatedWithWristY:(CGFloat)wristY isMovingDown:(BOOL)isMovingDown;

// Called when no person is detected in frame
- (void)personNotDetected;

@end

@interface BallBouncingDetector : NSObject

@property (nonatomic, weak) id<BallBouncingDetectorDelegate> delegate;
@property (nonatomic, readonly) NSInteger bounceCount;
@property (nonatomic, readonly) BOOL isDetecting;

// Sensitivity settings
@property (nonatomic, assign) CGFloat movementThreshold;  // Minimum movement to count as bounce
@property (nonatomic, assign) NSTimeInterval bounceTimeWindow;  // Time window for valid bounce

- (void)startDetection;
- (void)stopDetection;
- (void)resetBounceCount;

// Process video frame for pose detection
- (void)processPixelBuffer:(CVPixelBufferRef)pixelBuffer;

@end

NS_ASSUME_NONNULL_END
