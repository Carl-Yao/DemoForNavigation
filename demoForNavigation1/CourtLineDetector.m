//
//  CourtLineDetector.m
//  demoForNavigation1
//
//  Basketball court line detection using Core Image
//  Detects white/bright lines typical of basketball courts
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
        _threshold = 0.7;  // Brightness threshold for white line detection
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

    // Process every 2nd frame for performance
    self.frameCount++;
    if (self.frameCount % 2 != 0) {
        return;
    }

    [self detectCourtLinesInPixelBuffer:pixelBuffer];
}

- (void)detectCourtLinesInPixelBuffer:(CVPixelBufferRef)pixelBuffer {
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

    // Fix rotation: Camera outputs landscape, we need portrait
    inputImage = [inputImage imageByApplyingCGOrientation:kCGImagePropertyOrientationRight];

    CGRect extent = inputImage.extent;

    // Step 1: Enhance contrast to make white lines stand out
    CIFilter *colorControls = [CIFilter filterWithName:@"CIColorControls"];
    [colorControls setValue:inputImage forKey:kCIInputImageKey];
    [colorControls setValue:@(1.8) forKey:kCIInputContrastKey];
    [colorControls setValue:@(0.0) forKey:kCIInputBrightnessKey];
    [colorControls setValue:@(0.0) forKey:kCIInputSaturationKey];  // Grayscale
    CIImage *contrastImage = colorControls.outputImage;

    // Step 2: Threshold to isolate bright/white areas (court lines)
    // Using color matrix to create threshold effect
    // Pixels brighter than threshold become white, others become black
    CIFilter *thresholdFilter = [CIFilter filterWithName:@"CIColorMatrix"];
    [thresholdFilter setValue:contrastImage forKey:kCIInputImageKey];

    // High contrast to create threshold effect
    CGFloat scale = 10.0;  // High multiplier
    CGFloat bias = -self.threshold * scale;  // Offset based on threshold

    [thresholdFilter setValue:[CIVector vectorWithX:scale Y:0 Z:0 W:0] forKey:@"inputRVector"];
    [thresholdFilter setValue:[CIVector vectorWithX:0 Y:scale Z:0 W:0] forKey:@"inputGVector"];
    [thresholdFilter setValue:[CIVector vectorWithX:0 Y:0 Z:scale W:0] forKey:@"inputBVector"];
    [thresholdFilter setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:1] forKey:@"inputAVector"];
    [thresholdFilter setValue:[CIVector vectorWithX:bias Y:bias Z:bias W:0] forKey:@"inputBiasVector"];

    CIImage *thresholdedImage = thresholdFilter.outputImage;

    // Clamp values to 0-1 range
    CIFilter *clampFilter = [CIFilter filterWithName:@"CIColorClamp"];
    [clampFilter setValue:thresholdedImage forKey:kCIInputImageKey];
    [clampFilter setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:0] forKey:@"inputMinComponents"];
    [clampFilter setValue:[CIVector vectorWithX:1 Y:1 Z:1 W:1] forKey:@"inputMaxComponents"];
    CIImage *clampedImage = clampFilter.outputImage;

    // Step 3: Apply edge detection to find line boundaries
    CIFilter *edgesFilter = [CIFilter filterWithName:@"CIEdges"];
    [edgesFilter setValue:clampedImage forKey:kCIInputImageKey];
    [edgesFilter setValue:@(self.edgeIntensity * 3.0) forKey:kCIInputIntensityKey];
    CIImage *edgesImage = edgesFilter.outputImage;

    if (!edgesImage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(courtLineDetectionFailed:)]) {
                [self.delegate courtLineDetectionFailed:@"边缘检测失败"];
            }
        });
        return;
    }

    // Step 4: Enhance edge visibility
    CIFilter *exposureFilter = [CIFilter filterWithName:@"CIExposureAdjust"];
    [exposureFilter setValue:edgesImage forKey:kCIInputImageKey];
    [exposureFilter setValue:@(2.0) forKey:kCIInputEVKey];
    CIImage *enhancedEdges = exposureFilter.outputImage;

    // Step 5: Colorize the detected lines (make them cyan for visibility)
    CIFilter *colorMatrix = [CIFilter filterWithName:@"CIColorMatrix"];
    [colorMatrix setValue:enhancedEdges forKey:kCIInputImageKey];
    // Convert white edges to cyan color
    [colorMatrix setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:0] forKey:@"inputRVector"];
    [colorMatrix setValue:[CIVector vectorWithX:0 Y:1 Z:0 W:0] forKey:@"inputGVector"];
    [colorMatrix setValue:[CIVector vectorWithX:0 Y:0 Z:1 W:0] forKey:@"inputBVector"];
    [colorMatrix setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:1] forKey:@"inputAVector"];
    [colorMatrix setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:0] forKey:@"inputBiasVector"];
    CIImage *coloredEdges = colorMatrix.outputImage;

    CIImage *finalImage = coloredEdges;

    // If showing with original, blend
    if (self.showColorEdges) {
        CIFilter *blendFilter = [CIFilter filterWithName:@"CISourceOverCompositing"];
        [blendFilter setValue:coloredEdges forKey:kCIInputImageKey];
        [blendFilter setValue:inputImage forKey:kCIInputBackgroundImageKey];
        finalImage = blendFilter.outputImage;
    }

    // Render to UIImage
    CGImageRef cgImage = [self.ciContext createCGImage:finalImage fromRect:extent];

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
