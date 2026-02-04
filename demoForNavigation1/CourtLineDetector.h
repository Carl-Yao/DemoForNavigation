//
//  CourtLineDetector.h
//  demoForNavigation1
//
//  Basketball court line detection using Vision framework
//  Uses geometry rules to filter court lines (straight lines and arcs)
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Type of detected court line
typedef NS_ENUM(NSInteger, CourtLineType) {
    CourtLineTypeHorizontal,    // Horizontal straight line (baseline, free throw line, etc.)
    CourtLineTypeVertical,      // Vertical straight line (sideline, lane line, etc.)
    CourtLineTypeArc,           // Curved line (three-point arc, center circle, etc.)
    CourtLineTypeUnknown        // Unknown/filtered out
};

// Represents a detected court line
@interface DetectedCourtLine : NSObject

@property (nonatomic, strong) UIBezierPath *path;
@property (nonatomic, assign) CourtLineType lineType;
@property (nonatomic, assign) CGFloat length;           // Length of the line
@property (nonatomic, assign) CGFloat angle;            // Angle in degrees (for straight lines)
@property (nonatomic, assign) CGFloat straightness;     // How straight the line is (0-1, 1=perfectly straight)
@property (nonatomic, assign) CGPoint startPoint;
@property (nonatomic, assign) CGPoint endPoint;

@end

@protocol CourtLineDetectorDelegate <NSObject>

// Called when court lines are detected with classified lines
- (void)courtLinesDetected:(NSArray<DetectedCourtLine *> *)lines
                 imageSize:(CGSize)imageSize;

// Called when detection fails
- (void)courtLineDetectionFailed:(NSString *)reason;

@end

@interface CourtLineDetector : NSObject

@property (nonatomic, weak) id<CourtLineDetectorDelegate> delegate;
@property (nonatomic, readonly) BOOL isDetecting;

// Detection settings
@property (nonatomic, assign) CGFloat contrastAdjustment;       // Contrast for detection (default 1.5)
@property (nonatomic, assign) BOOL detectDarkOnLight;           // Dark lines on light background
@property (nonatomic, assign) CGFloat minLineLength;            // Minimum line length in normalized coords (default 0.1)
@property (nonatomic, assign) CGFloat angleThreshold;           // Angle tolerance for H/V lines in degrees (default 15)
@property (nonatomic, assign) CGFloat straightnessThreshold;    // Min straightness for straight lines (default 0.85)

- (void)startDetection;
- (void)stopDetection;

// Process video frame for court line detection
- (void)processPixelBuffer:(CVPixelBufferRef)pixelBuffer;

@end

NS_ASSUME_NONNULL_END
