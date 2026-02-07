//
//  CourtLineDetector.h
//  demoForNavigation1
//
//  Basketball court line detection using FIBA template matching
//  Matches standard court template against detected edges to find court position
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Court pose - position and orientation of court in image
@interface CourtPose : NSObject
@property (nonatomic, assign) CGFloat centerX;      // Court center X (0-1 normalized)
@property (nonatomic, assign) CGFloat centerY;      // Court center Y (0-1 normalized)
@property (nonatomic, assign) CGFloat rotation;     // Rotation in degrees (0-360)
@property (nonatomic, assign) CGFloat scale;        // Scale factor
@property (nonatomic, assign) CGFloat perspectiveX; // Perspective tilt X (-1 to 1)
@property (nonatomic, assign) CGFloat perspectiveY; // Perspective tilt Y (-1 to 1)
@property (nonatomic, assign) CGFloat matchScore;   // How well this pose matches (0-1)
@end

// FIBA half-court template line
@interface TemplateLine : NSObject
@property (nonatomic, assign) CGPoint start;  // Normalized coords (-0.5 to 0.5)
@property (nonatomic, assign) CGPoint end;
@property (nonatomic, strong) NSString *name; // Line identifier
+ (instancetype)lineFrom:(CGPoint)start to:(CGPoint)end name:(NSString *)name;
@end

// Projected line in image coordinates
@interface ProjectedLine : NSObject
@property (nonatomic, assign) CGPoint start;  // Image coords (0-1)
@property (nonatomic, assign) CGPoint end;
@property (nonatomic, strong) NSString *name;
@property (nonatomic, assign) BOOL isVisible; // Within image bounds
@end

// Detection result
@interface CourtDetectionResult : NSObject
@property (nonatomic, strong, nullable) CourtPose *bestPose;
@property (nonatomic, strong) NSArray<ProjectedLine *> *projectedLines;
@property (nonatomic, assign) BOOL courtFound;
@end

@protocol CourtLineDetectorDelegate <NSObject>
- (void)courtLineDetector:(id)detector didDetectResult:(CourtDetectionResult *)result;
- (void)courtLineDetectorDidFail:(id)detector withError:(NSString *)error;
@end

@interface CourtLineDetector : NSObject

@property (nonatomic, weak) id<CourtLineDetectorDelegate> delegate;
@property (nonatomic, readonly) BOOL isDetecting;

// Detection parameters
@property (nonatomic, assign) CGFloat edgeThreshold;    // Edge detection threshold (default 1.5)
@property (nonatomic, assign) CGFloat minMatchScore;    // Minimum score to consider match (default 0.3)

- (void)startDetection;
- (void)stopDetection;
- (void)processPixelBuffer:(CVPixelBufferRef)pixelBuffer;

@end

NS_ASSUME_NONNULL_END
