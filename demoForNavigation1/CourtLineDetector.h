//
//  CourtLineDetector.h
//  demoForNavigation1
//
//  Basketball court line detection using Core Image edge detection
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol CourtLineDetectorDelegate <NSObject>

// Called when lines are detected, returns the processed edge image
- (void)courtLineDetectorDidDetectEdges:(UIImage *)edgeImage;

// Called when detection fails
- (void)courtLineDetectionFailed:(NSString *)reason;

@end

@interface CourtLineDetector : NSObject

@property (nonatomic, weak) id<CourtLineDetectorDelegate> delegate;
@property (nonatomic, readonly) BOOL isDetecting;

// Detection settings
@property (nonatomic, assign) CGFloat edgeIntensity;      // Edge detection intensity (default 1.0)
@property (nonatomic, assign) CGFloat threshold;          // Edge threshold (default 0.1)
@property (nonatomic, assign) BOOL showColorEdges;        // Show edges in color (default NO)

- (void)startDetection;
- (void)stopDetection;

// Process video frame
- (void)processPixelBuffer:(CVPixelBufferRef)pixelBuffer;

@end

NS_ASSUME_NONNULL_END
