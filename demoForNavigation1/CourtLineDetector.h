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

NS_ASSUME_NONNULL_BEGIN

@protocol CourtLineDetectorDelegate <NSObject>

// Called when court lines are detected with processed image
- (void)courtLinesDetectedWithImage:(CIImage *)processedImage lineCount:(NSInteger)lineCount;

// Called when detection fails or no lines found
- (void)courtLineDetectionFailed:(NSString *)reason;

@end

@interface CourtLineDetector : NSObject

@property (nonatomic, weak) id<CourtLineDetectorDelegate> delegate;
@property (nonatomic, readonly) BOOL isDetecting;

// Detection settings
@property (nonatomic, assign) CGFloat edgeIntensity;      // Edge detection strength (0.0 - 1.0)
@property (nonatomic, assign) CGFloat lineThreshold;      // Minimum line length threshold
@property (nonatomic, assign) BOOL showOriginalOverlay;   // Show original image with overlay

- (void)startDetection;
- (void)stopDetection;

// Process video frame for court line detection
- (void)processPixelBuffer:(CVPixelBufferRef)pixelBuffer;

// Get the CIContext for rendering
- (CIContext *)ciContext;

@end

NS_ASSUME_NONNULL_END
