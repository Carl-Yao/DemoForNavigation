//
//  CourtLineDetector.h
//  demoForNavigation1
//
//  Basketball court line detection using Vision and Core Image
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <Vision/Vision.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol CourtLineDetectorDelegate <NSObject>

// Called when court lines are detected with contour paths for drawing
- (void)courtLinesDetectedWithContours:(NSArray<UIBezierPath *> *)contourPaths
                             lineCount:(NSInteger)lineCount
                             imageSize:(CGSize)imageSize;

// Called when detection fails or no lines found
- (void)courtLineDetectionFailed:(NSString *)reason;

@end

@interface CourtLineDetector : NSObject

@property (nonatomic, weak) id<CourtLineDetectorDelegate> delegate;
@property (nonatomic, readonly) BOOL isDetecting;

// Detection settings
@property (nonatomic, assign) CGFloat contrastAdjustment;   // Contrast for contour detection (default 2.0)
@property (nonatomic, assign) CGFloat simplificationEpsilon; // Path simplification (default 0.001)
@property (nonatomic, assign) BOOL detectDarkOnLight;       // Dark lines on light background

- (void)startDetection;
- (void)stopDetection;

// Process video frame for court line detection
- (void)processPixelBuffer:(CVPixelBufferRef)pixelBuffer;

@end

NS_ASSUME_NONNULL_END
