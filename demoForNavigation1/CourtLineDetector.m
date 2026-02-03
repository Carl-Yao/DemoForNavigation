//
//  CourtLineDetector.m
//  demoForNavigation1
//
//  Basketball court line detection using Vision and Core Image
//

#import "CourtLineDetector.h"

@interface CourtLineDetector ()

@property (nonatomic, assign) BOOL isDetecting;
@property (nonatomic, strong) CIContext *ciContext;
@property (nonatomic, assign) NSInteger frameCount;

// Core Image filters
@property (nonatomic, strong) CIFilter *edgeDetectionFilter;
@property (nonatomic, strong) CIFilter *colorControlsFilter;
@property (nonatomic, strong) CIFilter *exposureFilter;

@end

@implementation CourtLineDetector

- (instancetype)init {
    self = [super init];
    if (self) {
        _isDetecting = NO;
        _frameCount = 0;
        _edgeIntensity = 0.7;
        _lineThreshold = 0.1;
        _showOriginalOverlay = YES;

        [self setupCIContext];
        [self setupFilters];
    }
    return self;
}

- (void)setupCIContext {
    // Create CIContext with GPU rendering for better performance
    NSDictionary *options = @{kCIContextUseSoftwareRenderer: @NO};
    self.ciContext = [CIContext contextWithOptions:options];
}

- (void)setupFilters {
    // Edge detection using Sobel-like convolution
    self.edgeDetectionFilter = [CIFilter filterWithName:@"CIEdges"];

    // Color controls for enhancing contrast
    self.colorControlsFilter = [CIFilter filterWithName:@"CIColorControls"];

    // Exposure adjustment
    self.exposureFilter = [CIFilter filterWithName:@"CIExposureAdjust"];
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

    CIImage *inputImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];

    if (!inputImage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(courtLineDetectionFailed:)]) {
                [self.delegate courtLineDetectionFailed:@"无法获取图像"];
            }
        });
        return;
    }

    // Process the image to detect lines
    CIImage *processedImage = [self detectLinesInImage:inputImage];
    NSInteger lineCount = [self estimateLineCount:processedImage];

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(courtLinesDetectedWithImage:lineCount:)]) {
            [self.delegate courtLinesDetectedWithImage:processedImage lineCount:lineCount];
        }
    });
}

- (CIImage *)detectLinesInImage:(CIImage *)inputImage {
    // Step 1: Enhance contrast to make lines more visible
    [self.colorControlsFilter setValue:inputImage forKey:kCIInputImageKey];
    [self.colorControlsFilter setValue:@(1.2) forKey:kCIInputContrastKey];
    [self.colorControlsFilter setValue:@(0.0) forKey:kCIInputSaturationKey]; // Grayscale
    [self.colorControlsFilter setValue:@(0.1) forKey:kCIInputBrightnessKey];
    CIImage *contrastImage = self.colorControlsFilter.outputImage;

    // Step 2: Apply edge detection
    [self.edgeDetectionFilter setValue:contrastImage forKey:kCIInputImageKey];
    [self.edgeDetectionFilter setValue:@(self.edgeIntensity * 10.0) forKey:@"inputIntensity"];
    CIImage *edgeImage = self.edgeDetectionFilter.outputImage;

    // Step 3: Enhance edges with exposure
    [self.exposureFilter setValue:edgeImage forKey:kCIInputImageKey];
    [self.exposureFilter setValue:@(1.5) forKey:kCIInputEVKey];
    CIImage *enhancedEdges = self.exposureFilter.outputImage;

    if (self.showOriginalOverlay) {
        // Blend edges with original image for better visualization
        CIFilter *blendFilter = [CIFilter filterWithName:@"CIScreenBlendMode"];
        [blendFilter setValue:inputImage forKey:kCIInputImageKey];
        [blendFilter setValue:enhancedEdges forKey:kCIInputBackgroundImageKey];
        return blendFilter.outputImage ?: enhancedEdges;
    }

    return enhancedEdges;
}

- (NSInteger)estimateLineCount:(CIImage *)processedImage {
    // Use Vision framework to detect contours/rectangles as a proxy for line count
    if (@available(iOS 14.0, *)) {
        __block NSInteger count = 0;

        VNDetectContoursRequest *contoursRequest = [[VNDetectContoursRequest alloc] initWithCompletionHandler:^(VNRequest * _Nonnull request, NSError * _Nullable error) {
            if (error) {
                return;
            }

            for (VNContoursObservation *observation in request.results) {
                count += observation.contourCount;
            }
        }];

        contoursRequest.contrastAdjustment = 1.5;
        contoursRequest.detectsDarkOnLight = NO;

        CGImageRef cgImage = [self.ciContext createCGImage:processedImage fromRect:processedImage.extent];
        if (cgImage) {
            VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cgImage options:@{}];
            [handler performRequests:@[contoursRequest] error:nil];
            CGImageRelease(cgImage);
        }

        // Return a normalized count (contours can be many)
        return MIN(count, 50);
    }

    return 0;
}

@end
