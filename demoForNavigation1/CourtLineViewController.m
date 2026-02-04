//
//  CourtLineViewController.m
//  demoForNavigation1
//
//  View controller for basketball court line detection with camera
//

#import "CourtLineViewController.h"
#import "CourtLineDetector.h"
#import <AVFoundation/AVFoundation.h>

@interface CourtLineViewController () <AVCaptureVideoDataOutputSampleBufferDelegate, CourtLineDetectorDelegate>

// Camera
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) dispatch_queue_t videoQueue;

// Detector
@property (nonatomic, strong) CourtLineDetector *detector;

// Line drawing layer
@property (nonatomic, strong) CAShapeLayer *lineOverlayLayer;

// UI Elements
@property (nonatomic, strong) UIView *cameraContainerView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *lineCountLabel;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UISlider *contrastSlider;
@property (nonatomic, strong) UILabel *contrastLabel;
@property (nonatomic, strong) UISegmentedControl *modeSegment;
@property (nonatomic, strong) UILabel *modeLabel;

@property (nonatomic, assign) BOOL isRunning;

@end

@implementation CourtLineViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"场地线识别";
    self.view.backgroundColor = [UIColor blackColor];
    self.isRunning = NO;

    [self setupDetector];
    [self setupUI];
    [self setupLineOverlayLayer];
    [self checkCameraPermission];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopCamera];
}

- (void)dealloc {
    [self stopCamera];
}

#pragma mark - Setup

- (void)setupDetector {
    self.detector = [[CourtLineDetector alloc] init];
    self.detector.delegate = self;
    self.detector.contrastAdjustment = 2.0;
    self.detector.detectDarkOnLight = YES;
}

- (void)setupUI {
    // Camera container view
    self.cameraContainerView = [[UIView alloc] init];
    self.cameraContainerView.backgroundColor = [UIColor darkGrayColor];
    self.cameraContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cameraContainerView.clipsToBounds = YES;
    self.cameraContainerView.layer.cornerRadius = 8;
    [self.view addSubview:self.cameraContainerView];

    // Status label
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"准备就绪";
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:16];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];

    // Line count label
    self.lineCountLabel = [[UILabel alloc] init];
    self.lineCountLabel.text = @"检测到轮廓: 0";
    self.lineCountLabel.textColor = [UIColor greenColor];
    self.lineCountLabel.textAlignment = NSTextAlignmentCenter;
    self.lineCountLabel.font = [UIFont boldSystemFontOfSize:22];
    self.lineCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.lineCountLabel];

    // Contrast slider label
    self.contrastLabel = [[UILabel alloc] init];
    self.contrastLabel.text = @"对比度: 2.0";
    self.contrastLabel.textColor = [UIColor lightGrayColor];
    self.contrastLabel.font = [UIFont systemFontOfSize:14];
    self.contrastLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.contrastLabel];

    // Contrast slider
    self.contrastSlider = [[UISlider alloc] init];
    self.contrastSlider.minimumValue = 0.5;
    self.contrastSlider.maximumValue = 3.0;
    self.contrastSlider.value = 2.0;
    self.contrastSlider.tintColor = [UIColor cyanColor];
    self.contrastSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contrastSlider addTarget:self action:@selector(contrastChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.contrastSlider];

    // Mode label
    self.modeLabel = [[UILabel alloc] init];
    self.modeLabel.text = @"检测模式:";
    self.modeLabel.textColor = [UIColor lightGrayColor];
    self.modeLabel.font = [UIFont systemFontOfSize:14];
    self.modeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.modeLabel];

    // Mode segment control
    self.modeSegment = [[UISegmentedControl alloc] initWithItems:@[@"深线/浅底", @"浅线/深底"]];
    self.modeSegment.selectedSegmentIndex = 0;
    self.modeSegment.translatesAutoresizingMaskIntoConstraints = NO;
    [self.modeSegment addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.modeSegment];

    // Start/Stop button
    self.startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.startButton setTitle:@"开始检测" forState:UIControlStateNormal];
    [self.startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:0.9 alpha:1.0];
    self.startButton.layer.cornerRadius = 25;
    self.startButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.startButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.startButton addTarget:self action:@selector(toggleDetection) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.startButton];

    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // Camera container
        [self.cameraContainerView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [self.cameraContainerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.cameraContainerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.cameraContainerView.heightAnchor constraintEqualToAnchor:self.cameraContainerView.widthAnchor multiplier:0.75],

        // Status label
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.cameraContainerView.bottomAnchor constant:15],
        [self.statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        // Line count label
        [self.lineCountLabel.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:8],
        [self.lineCountLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        // Contrast label
        [self.contrastLabel.topAnchor constraintEqualToAnchor:self.lineCountLabel.bottomAnchor constant:20],
        [self.contrastLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],

        // Contrast slider
        [self.contrastSlider.centerYAnchor constraintEqualToAnchor:self.contrastLabel.centerYAnchor],
        [self.contrastSlider.leadingAnchor constraintEqualToAnchor:self.contrastLabel.trailingAnchor constant:10],
        [self.contrastSlider.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        // Mode label
        [self.modeLabel.topAnchor constraintEqualToAnchor:self.contrastLabel.bottomAnchor constant:15],
        [self.modeLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],

        // Mode segment
        [self.modeSegment.centerYAnchor constraintEqualToAnchor:self.modeLabel.centerYAnchor],
        [self.modeSegment.leadingAnchor constraintEqualToAnchor:self.modeLabel.trailingAnchor constant:10],
        [self.modeSegment.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        // Start button
        [self.startButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-30],
        [self.startButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.startButton.widthAnchor constraintEqualToConstant:200],
        [self.startButton.heightAnchor constraintEqualToConstant:50],
    ]];
}

- (void)setupLineOverlayLayer {
    self.lineOverlayLayer = [CAShapeLayer layer];
    self.lineOverlayLayer.strokeColor = [UIColor cyanColor].CGColor;
    self.lineOverlayLayer.fillColor = [UIColor clearColor].CGColor;
    self.lineOverlayLayer.lineWidth = 2.0;
    self.lineOverlayLayer.lineCap = kCALineCapRound;
    self.lineOverlayLayer.lineJoin = kCALineJoinRound;
}

#pragma mark - Camera Setup

- (void)checkCameraPermission {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];

    switch (status) {
        case AVAuthorizationStatusAuthorized:
            [self setupCamera];
            break;
        case AVAuthorizationStatusNotDetermined: {
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (granted) {
                        [self setupCamera];
                    } else {
                        [self showCameraPermissionAlert];
                    }
                });
            }];
            break;
        }
        default:
            [self showCameraPermissionAlert];
            break;
    }
}

- (void)showCameraPermissionAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"需要相机权限"
                                                                   message:@"请在设置中允许访问相机以使用场地线识别功能"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];

    self.statusLabel.text = @"需要相机权限";
}

- (void)setupCamera {
    self.captureSession = [[AVCaptureSession alloc] init];
    self.captureSession.sessionPreset = AVCaptureSessionPreset1280x720;

    AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                                 mediaType:AVMediaTypeVideo
                                                                  position:AVCaptureDevicePositionBack];

    if (!camera) {
        self.statusLabel.text = @"无法访问相机";
        return;
    }

    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error];

    if (error) {
        self.statusLabel.text = @"相机错误";
        return;
    }

    if ([self.captureSession canAddInput:input]) {
        [self.captureSession addInput:input];
    }

    // Video output
    AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    videoOutput.videoSettings = @{(NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
    videoOutput.alwaysDiscardsLateVideoFrames = YES;

    self.videoQueue = dispatch_queue_create("com.demo.courtLineQueue", DISPATCH_QUEUE_SERIAL);
    [videoOutput setSampleBufferDelegate:self queue:self.videoQueue];

    if ([self.captureSession canAddOutput:videoOutput]) {
        [self.captureSession addOutput:videoOutput];
    }

    // Preview layer
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.cameraContainerView.layer addSublayer:self.previewLayer];

    // Add line overlay layer on top of preview
    [self.cameraContainerView.layer addSublayer:self.lineOverlayLayer];

    // Start session on background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.captureSession startRunning];
    });

    self.statusLabel.text = @"相机已就绪";
}

- (void)stopCamera {
    if (self.captureSession.isRunning) {
        [self.captureSession stopRunning];
    }
    [self.detector stopDetection];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.previewLayer.frame = self.cameraContainerView.bounds;
    self.lineOverlayLayer.frame = self.cameraContainerView.bounds;
}

#pragma mark - Actions

- (void)toggleDetection {
    if (self.isRunning) {
        [self.detector stopDetection];
        self.isRunning = NO;
        [self.startButton setTitle:@"开始检测" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:0.9 alpha:1.0];
        self.statusLabel.text = @"已暂停";
        self.lineOverlayLayer.path = nil;
    } else {
        [self.detector startDetection];
        self.isRunning = YES;
        [self.startButton setTitle:@"停止检测" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:1.0];
        self.statusLabel.text = @"检测中...";
    }
}

- (void)contrastChanged:(UISlider *)slider {
    self.detector.contrastAdjustment = slider.value;
    self.contrastLabel.text = [NSString stringWithFormat:@"对比度: %.1f", slider.value];
}

- (void)modeChanged:(UISegmentedControl *)segment {
    self.detector.detectDarkOnLight = (segment.selectedSegmentIndex == 0);
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {

    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (pixelBuffer) {
        [self.detector processPixelBuffer:pixelBuffer];
    }
}

#pragma mark - CourtLineDetectorDelegate

- (void)courtLinesDetectedWithContours:(NSArray<UIBezierPath *> *)contourPaths
                             lineCount:(NSInteger)lineCount
                             imageSize:(CGSize)imageSize {
    // Update UI
    self.lineCountLabel.text = [NSString stringWithFormat:@"检测到轮廓: %ld", (long)lineCount];

    // Update color based on line count
    if (lineCount > 5) {
        self.lineCountLabel.textColor = [UIColor greenColor];
        self.statusLabel.text = @"检测到场地线";
        self.lineOverlayLayer.strokeColor = [UIColor cyanColor].CGColor;
    } else if (lineCount > 0) {
        self.lineCountLabel.textColor = [UIColor yellowColor];
        self.statusLabel.text = @"检测中...";
        self.lineOverlayLayer.strokeColor = [UIColor yellowColor].CGColor;
    } else {
        self.lineCountLabel.textColor = [UIColor redColor];
        self.statusLabel.text = @"未检测到明显线条";
        self.lineOverlayLayer.path = nil;
        return;
    }

    // Draw contours on the overlay layer
    [self drawContours:contourPaths imageSize:imageSize];
}

- (void)drawContours:(NSArray<UIBezierPath *> *)contourPaths imageSize:(CGSize)imageSize {
    CGRect layerBounds = self.lineOverlayLayer.bounds;

    if (CGRectIsEmpty(layerBounds) || imageSize.width == 0 || imageSize.height == 0) {
        return;
    }

    UIBezierPath *combinedPath = [UIBezierPath bezierPath];

    // Vision normalized coordinates: (0,0) is bottom-left, (1,1) is top-right
    // We need to transform to layer coordinates
    // Also account for video orientation (landscape input displayed in portrait view)

    CGFloat viewWidth = layerBounds.size.width;
    CGFloat viewHeight = layerBounds.size.height;

    for (UIBezierPath *normalizedPath in contourPaths) {
        // Create a transform to scale from normalized coordinates to view coordinates
        // Vision coordinates have Y flipped (0 at bottom)
        CGAffineTransform transform = CGAffineTransformIdentity;

        // For landscape video in portrait view, we need to rotate and scale
        // Normalized coords (0-1) need to map to view coords
        // Since camera is landscape, width maps to height and vice versa

        // Scale to view size (swap width/height for rotation)
        transform = CGAffineTransformScale(transform, viewHeight, viewWidth);

        // Rotate 90 degrees clockwise and translate
        transform = CGAffineTransformRotate(transform, M_PI_2);
        transform = CGAffineTransformTranslate(transform, 0, -1);

        UIBezierPath *transformedPath = [normalizedPath copy];
        [transformedPath applyTransform:transform];

        [combinedPath appendPath:transformedPath];
    }

    // Animate the path update for smoother visualization
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"path"];
    animation.fromValue = (__bridge id)self.lineOverlayLayer.path;
    animation.toValue = (__bridge id)combinedPath.CGPath;
    animation.duration = 0.1;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];

    self.lineOverlayLayer.path = combinedPath.CGPath;
    [self.lineOverlayLayer addAnimation:animation forKey:@"pathAnimation"];
}

- (void)courtLineDetectionFailed:(NSString *)reason {
    self.statusLabel.text = reason;
    self.lineCountLabel.textColor = [UIColor redColor];
    self.lineOverlayLayer.path = nil;
}

@end
