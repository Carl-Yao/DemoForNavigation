//
//  CourtLineDetector.m
//  demoForNavigation1
//
//  Basketball court line detection using Core Image edge detection
//  Uses Sobel-based edge detection to find court lines
//

#import "CourtLineDetector.h"

@interface CourtLineDetector ()

@property (nonatomic, assign) BOOL isDetecting;
@property (nonatomic, assign) NSInteger frameCount;
@property (nonatomic, strong) CIContext *ciContext;

@end

@implementation CourtLineDetector

- (instancetype)init {
    self = [super init];
    if (self) {
        _isDetecting = NO;
        _frameCount = 0;
        _edgeIntensity = 1.0;
        _threshold = 0.1;
        _showColorEdges = NO;

        // Create CIContext for GPU-accelerated processing
        _ciContext = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}];
    }
    return self;
}

- (void)startDetection {
    self.isDetecting = YES;
    self.frameCount = 0;
}

- (void)stopDetection {
    self.isDetecting = NO;
}

- (void)processPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!self.isDetecting) {
        return;
    }

    // Process every 2nd frame for better performance while maintaining smoothness
    self.frameCount++;
    if (self.frameCount % 2 != 0) {
        return;
    }

    [self detectEdgesInPixelBuffer:pixelBuffer];
}

- (void)detectEdgesInPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    // Create CIImage from pixel buffer
    CIImage *inputImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];

    if (!inputImage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(courtLineDetectionFailed:)]) {
                [self.delegate courtLineDetectionFailed:@"无法处理图像"];
            }
        });
        return;
    }

    // Step 1: Convert to grayscale and enhance contrast
    CIFilter *colorControls = [CIFilter filterWithName:@"CIColorControls"];
    [colorControls setValue:inputImage forKey:kCIInputImageKey];
    [colorControls setValue:@(0.0) forKey:kCIInputSaturationKey];  // Grayscale
    [colorControls setValue:@(1.2) forKey:kCIInputContrastKey];    // Increase contrast
    [colorControls setValue:@(0.0) forKey:kCIInputBrightnessKey];
    CIImage *grayscaleImage = colorControls.outputImage;

    // Step 2: Apply edge detection using CIEdges
    CIFilter *edgesFilter = [CIFilter filterWithName:@"CIEdges"];
    [edgesFilter setValue:grayscaleImage forKey:kCIInputImageKey];
    [edgesFilter setValue:@(self.edgeIntensity) forKey:kCIInputIntensityKey];
    CIImage *edgesImage = edgesFilter.outputImage;

    if (!edgesImage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(courtLineDetectionFailed:)]) {
                [self.delegate courtLineDetectionFailed:@"边缘检测失败"];
            }
        });
        return;
    }

    // Step 3: Enhance the edges
    CIFilter *exposureFilter = [CIFilter filterWithName:@"CIExposureAdjust"];
    [exposureFilter setValue:edgesImage forKey:kCIInputImageKey];
    [exposureFilter setValue:@(1.5) forKey:kCIInputEVKey];  // Brighten edges
    CIImage *enhancedEdges = exposureFilter.outputImage;

    // Step 4: Apply threshold to get cleaner lines
    // Using CIColorMatrix to threshold
    CIFilter *thresholdFilter = [CIFilter filterWithName:@"CIColorMatrix"];
    [thresholdFilter setValue:enhancedEdges forKey:kCIInputImageKey];

    // Make edges more visible by boosting contrast
    CGFloat boost = 2.0;
    [thresholdFilter setValue:[CIVector vectorWithX:boost Y:0 Z:0 W:0] forKey:@"inputRVector"];
    [thresholdFilter setValue:[CIVector vectorWithX:0 Y:boost Z:0 W:0] forKey:@"inputGVector"];
    [thresholdFilter setValue:[CIVector vectorWithX:0 Y:0 Z:boost W:0] forKey:@"inputBVector"];
    [thresholdFilter setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:1] forKey:@"inputAVector"];
    [thresholdFilter setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:0] forKey:@"inputBiasVector"];

    CIImage *finalImage = thresholdFilter.outputImage;

    // If showing color edges, blend with original
    if (self.showColorEdges) {
        CIFilter *blendFilter = [CIFilter filterWithName:@"CIAdditionCompositing"];
        [blendFilter setValue:finalImage forKey:kCIInputImageKey];
        [blendFilter setValue:inputImage forKey:kCIInputBackgroundImageKey];
        finalImage = blendFilter.outputImage;
    }

    // Render to UIImage
    CGImageRef cgImage = [self.ciContext createCGImage:finalImage fromRect:inputImage.extent];

    if (!cgImage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(courtLineDetectionFailed:)]) {
                [self.delegate courtLineDetectionFailed:@"图像渲染失败"];
            }
        });
        return;
    }

    UIImage *outputImage = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);

    // Notify delegate on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(courtLineDetectorDidDetectEdges:)]) {
            [self.delegate courtLineDetectorDidDetectEdges:outputImage];
        }
    });
}

@end
