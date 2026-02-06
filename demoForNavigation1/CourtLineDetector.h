//
//  CourtLineDetector.h
//  demoForNavigation1
//
//  Basketball court line detection based on FIBA half-court geometry
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Detected court line types based on FIBA half-court
typedef NS_ENUM(NSInteger, CourtLineType) {
    CourtLineTypeBaseline,        // Bottom horizontal line
    CourtLineTypeHalfCourtLine,   // Top horizontal line (half-court)
    CourtLineTypeSideline,        // Left/right vertical lines
    CourtLineTypeFreeThrowLine,   // Free throw line (horizontal)
    CourtLineTypeLaneLine,        // Free throw lane lines (vertical)
    CourtLineTypeThreePointArc,   // Three-point arc
    CourtLineTypeOther            // Unclassified line
};

// Represents a detected line segment
@interface DetectedLine : NSObject
@property (nonatomic, assign) CGPoint startPoint;   // Normalized 0-1
@property (nonatomic, assign) CGPoint endPoint;     // Normalized 0-1
@property (nonatomic, assign) CGFloat angle;        // Degrees 0-180
@property (nonatomic, assign) CGFloat length;       // Normalized length
@property (nonatomic, assign) BOOL isHorizontal;
@property (nonatomic, assign) BOOL isVertical;
@property (nonatomic, assign) CourtLineType lineType;
@end

// Represents detected court structure
@interface DetectedCourt : NSObject
@property (nonatomic, strong) NSArray<DetectedLine *> *horizontalLines;
@property (nonatomic, strong) NSArray<DetectedLine *> *verticalLines;
@property (nonatomic, strong) NSArray<DetectedLine *> *arcLines;
@property (nonatomic, assign) BOOL isCourtDetected;
@property (nonatomic, assign) CGRect courtBounds;   // Normalized bounds of detected court
@end

@protocol CourtLineDetectorDelegate <NSObject>
- (void)courtLineDetector:(id)detector didDetectCourt:(DetectedCourt *)court inImageSize:(CGSize)imageSize;
- (void)courtLineDetectionFailed:(NSString *)reason;
@end

@interface CourtLineDetector : NSObject

@property (nonatomic, weak) id<CourtLineDetectorDelegate> delegate;
@property (nonatomic, readonly) BOOL isDetecting;

// Detection parameters
@property (nonatomic, assign) CGFloat contrastAdjustment;   // Default 1.5
@property (nonatomic, assign) CGFloat minLineLength;        // Min line length ratio (default 0.1)
@property (nonatomic, assign) CGFloat angleThreshold;       // Angle tolerance in degrees (default 15)

- (void)startDetection;
- (void)stopDetection;
- (void)processPixelBuffer:(CVPixelBufferRef)pixelBuffer;

@end

NS_ASSUME_NONNULL_END
