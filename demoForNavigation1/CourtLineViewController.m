//
//  CourtLineViewController.m
//  demoForNavigation1
//
//  View controller for basketball court line detection with camera
//  Displays detected lines with color coding by type
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

// Line drawing layers - separate layers for each line type
@property (nonatomic, strong) CAShapeLayer *horizontalLineLayer;
@property (nonatomic, strong) CAShapeLayer *verticalLineLayer;
@property (nonatomic, strong) CAShapeLayer *arcLineLayer;

// UI Elements
@property (nonatomic, strong) UIView *cameraContainerView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *lineCountLabel;
@property (nonatomic, strong) UILabel *lineDetailLabel;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UISlider *contrastSlider;
@property (nonatomic, strong) UILabel *contrastLabel;
@property (nonatomic, strong) UISlider *sensitivitySlider;
@property (nonatomic, strong) UILabel *sensitivityLabel;

// Legend labels
@property (nonatomic, strong) UIView *legendView;

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
    [self setupLineLayers];
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
    // Use more lenient default values for better detection
    self.detector.contrastAdjustment = 2.0;
    self.detector.detectDarkOnLight = YES;  // Try dark on light first
    self.detector.minLineLength = 0.05;     // Lower threshold
    self.detector.straightnessThreshold = 0.75;  // More lenient
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
    self.lineCountLabel.text = @"场地线: 0";
    self.lineCountLabel.textColor = [UIColor greenColor];
    self.lineCountLabel.textAlignment = NSTextAlignmentCenter;
    self.lineCountLabel.font = [UIFont boldSystemFontOfSize:22];
    self.lineCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.lineCountLabel];

    // Line detail label
    self.lineDetailLabel = [[UILabel alloc] init];
    self.lineDetailLabel.text = @"横线: 0  竖线: 0  弧线: 0";
    self.lineDetailLabel.textColor = [UIColor lightGrayColor];
    self.lineDetailLabel.textAlignment = NSTextAlignmentCenter;
    self.lineDetailLabel.font = [UIFont systemFontOfSize:14];
    self.lineDetailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.lineDetailLabel];

    // Legend view
    [self setupLegendView];

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
    self.contrastSlider.value = 2.0;  // Higher default contrast
    self.contrastSlider.tintColor = [UIColor cyanColor];
    self.contrastSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contrastSlider addTarget:self action:@selector(contrastChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.contrastSlider];

    // Sensitivity slider label
    self.sensitivityLabel = [[UILabel alloc] init];
    self.sensitivityLabel.text = @"灵敏度: 75%";
    self.sensitivityLabel.textColor = [UIColor lightGrayColor];
    self.sensitivityLabel.font = [UIFont systemFontOfSize:14];
    self.sensitivityLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.sensitivityLabel];

    // Sensitivity slider (controls straightness threshold - lower = more lines detected)
    self.sensitivitySlider = [[UISlider alloc] init];
    self.sensitivitySlider.minimumValue = 0.5;   // More lenient minimum
    self.sensitivitySlider.maximumValue = 0.95;
    self.sensitivitySlider.value = 0.75;  // Lower default for more detections
    self.sensitivitySlider.tintColor = [UIColor yellowColor];
    self.sensitivitySlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.sensitivitySlider addTarget:self action:@selector(sensitivityChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.sensitivitySlider];

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
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.cameraContainerView.bottomAnchor constant:10],
        [self.statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        // Line count label
        [self.lineCountLabel.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:5],
        [self.lineCountLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        // Line detail label
        [self.lineDetailLabel.topAnchor constraintEqualToAnchor:self.lineCountLabel.bottomAnchor constant:3],
        [self.lineDetailLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        // Legend view
        [self.legendView.topAnchor constraintEqualToAnchor:self.lineDetailLabel.bottomAnchor constant:10],
        [self.legendView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.legendView.heightAnchor constraintEqualToConstant:24],

        // Contrast label
        [self.contrastLabel.topAnchor constraintEqualToAnchor:self.legendView.bottomAnchor constant:15],
        [self.contrastLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.contrastLabel.widthAnchor constraintEqualToConstant:90],

        // Contrast slider
        [self.contrastSlider.centerYAnchor constraintEqualToAnchor:self.contrastLabel.centerYAnchor],
        [self.contrastSlider.leadingAnchor constraintEqualToAnchor:self.contrastLabel.trailingAnchor constant:10],
        [self.contrastSlider.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        // Sensitivity label
        [self.sensitivityLabel.topAnchor constraintEqualToAnchor:self.contrastLabel.bottomAnchor constant:12],
        [self.sensitivityLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.sensitivityLabel.widthAnchor constraintEqualToConstant:90],

        // Sensitivity slider
        [self.sensitivitySlider.centerYAnchor constraintEqualToAnchor:self.sensitivityLabel.centerYAnchor],
        [self.sensitivitySlider.leadingAnchor constraintEqualToAnchor:self.sensitivityLabel.trailingAnchor constant:10],
        [self.sensitivitySlider.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        // Start button
        [self.startButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
        [self.startButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.startButton.widthAnchor constraintEqualToConstant:200],
        [self.startButton.heightAnchor constraintEqualToConstant:50],
    ]];
}

- (void)setupLegendView {
    self.legendView = [[UIView alloc] init];
    self.legendView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.legendView];

    // Horizontal line legend
    UIView *hColorBox = [[UIView alloc] initWithFrame:CGRectMake(0, 5, 14, 14)];
    hColorBox.backgroundColor = [UIColor cyanColor];
    hColorBox.layer.cornerRadius = 2;
    [self.legendView addSubview:hColorBox];

    UILabel *hLabel = [[UILabel alloc] initWithFrame:CGRectMake(18, 3, 40, 18)];
    hLabel.text = @"横线";
    hLabel.textColor = [UIColor whiteColor];
    hLabel.font = [UIFont systemFontOfSize:12];
    [self.legendView addSubview:hLabel];

    // Vertical line legend
    UIView *vColorBox = [[UIView alloc] initWithFrame:CGRectMake(70, 5, 14, 14)];
    vColorBox.backgroundColor = [UIColor greenColor];
    vColorBox.layer.cornerRadius = 2;
    [self.legendView addSubview:vColorBox];

    UILabel *vLabel = [[UILabel alloc] initWithFrame:CGRectMake(88, 3, 40, 18)];
    vLabel.text = @"竖线";
    vLabel.textColor = [UIColor whiteColor];
    vLabel.font = [UIFont systemFontOfSize:12];
    [self.legendView addSubview:vLabel];

    // Arc legend
    UIView *aColorBox = [[UIView alloc] initWithFrame:CGRectMake(140, 5, 14, 14)];
    aColorBox.backgroundColor = [UIColor yellowColor];
    aColorBox.layer.cornerRadius = 7;
    [self.legendView addSubview:aColorBox];

    UILabel *aLabel = [[UILabel alloc] initWithFrame:CGRectMake(158, 3, 40, 18)];
    aLabel.text = @"弧线";
    aLabel.textColor = [UIColor whiteColor];
    aLabel.font = [UIFont systemFontOfSize:12];
    [self.legendView addSubview:aLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.legendView.widthAnchor constraintEqualToConstant:200]
    ]];
}

- (void)setupLineLayers {
    // Horizontal lines layer (cyan)
    self.horizontalLineLayer = [CAShapeLayer layer];
    self.horizontalLineLayer.strokeColor = [UIColor cyanColor].CGColor;
    self.horizontalLineLayer.fillColor = [UIColor clearColor].CGColor;
    self.horizontalLineLayer.lineWidth = 3.0;
    self.horizontalLineLayer.lineCap = kCALineCapRound;

    // Vertical lines layer (green)
    self.verticalLineLayer = [CAShapeLayer layer];
    self.verticalLineLayer.strokeColor = [UIColor greenColor].CGColor;
    self.verticalLineLayer.fillColor = [UIColor clearColor].CGColor;
    self.verticalLineLayer.lineWidth = 3.0;
    self.verticalLineLayer.lineCap = kCALineCapRound;

    // Arc lines layer (yellow)
    self.arcLineLayer = [CAShapeLayer layer];
    self.arcLineLayer.strokeColor = [UIColor yellowColor].CGColor;
    self.arcLineLayer.fillColor = [UIColor clearColor].CGColor;
    self.arcLineLayer.lineWidth = 3.0;
    self.arcLineLayer.lineCap = kCALineCapRound;
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

    // Add line overlay layers on top of preview
    [self.cameraContainerView.layer addSublayer:self.horizontalLineLayer];
    [self.cameraContainerView.layer addSublayer:self.verticalLineLayer];
    [self.cameraContainerView.layer addSublayer:self.arcLineLayer];

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
    self.horizontalLineLayer.frame = self.cameraContainerView.bounds;
    self.verticalLineLayer.frame = self.cameraContainerView.bounds;
    self.arcLineLayer.frame = self.cameraContainerView.bounds;
}

#pragma mark - Actions

- (void)toggleDetection {
    if (self.isRunning) {
        [self.detector stopDetection];
        self.isRunning = NO;
        [self.startButton setTitle:@"开始检测" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:0.9 alpha:1.0];
        self.statusLabel.text = @"已暂停";
        [self clearLineLayers];
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

- (void)sensitivityChanged:(UISlider *)slider {
    self.detector.straightnessThreshold = slider.value;
    NSInteger percentage = (NSInteger)(slider.value * 100);
    self.sensitivityLabel.text = [NSString stringWithFormat:@"灵敏度: %ld%%", (long)percentage];
}

- (void)clearLineLayers {
    self.horizontalLineLayer.path = nil;
    self.verticalLineLayer.path = nil;
    self.arcLineLayer.path = nil;
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {

    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (pixelBuffer) {
        [self.detector processPixelBuffer:pixelBuffer];
    }
}

#pragma mark - CourtLineDetectorDelegate

- (void)courtLinesDetected:(NSArray<DetectedCourtLine *> *)lines
                 imageSize:(CGSize)imageSize {

    // Count lines by type
    NSInteger horizontalCount = 0;
    NSInteger verticalCount = 0;
    NSInteger arcCount = 0;

    UIBezierPath *horizontalPath = [UIBezierPath bezierPath];
    UIBezierPath *verticalPath = [UIBezierPath bezierPath];
    UIBezierPath *arcPath = [UIBezierPath bezierPath];

    CGRect layerBounds = self.horizontalLineLayer.bounds;
    if (CGRectIsEmpty(layerBounds)) {
        return;
    }

    CGFloat viewWidth = layerBounds.size.width;
    CGFloat viewHeight = layerBounds.size.height;

    for (DetectedCourtLine *line in lines) {
        if (!line.path) continue;

        // Transform the path to screen coordinates
        UIBezierPath *transformedPath = [self transformPath:line.path
                                                  viewWidth:viewWidth
                                                 viewHeight:viewHeight];

        switch (line.lineType) {
            case CourtLineTypeHorizontal:
                [horizontalPath appendPath:transformedPath];
                horizontalCount++;
                break;
            case CourtLineTypeVertical:
                [verticalPath appendPath:transformedPath];
                verticalCount++;
                break;
            case CourtLineTypeArc:
                [arcPath appendPath:transformedPath];
                arcCount++;
                break;
            default:
                break;
        }
    }

    // Update UI
    NSInteger totalCount = horizontalCount + verticalCount + arcCount;
    self.lineCountLabel.text = [NSString stringWithFormat:@"场地线: %ld", (long)totalCount];
    self.lineDetailLabel.text = [NSString stringWithFormat:@"横线: %ld  竖线: %ld  弧线: %ld",
                                 (long)horizontalCount, (long)verticalCount, (long)arcCount];

    // Update color based on detection quality
    if (totalCount >= 3) {
        self.lineCountLabel.textColor = [UIColor greenColor];
        self.statusLabel.text = @"检测到场地线";
    } else if (totalCount > 0) {
        self.lineCountLabel.textColor = [UIColor yellowColor];
        self.statusLabel.text = @"检测中...";
    } else {
        self.lineCountLabel.textColor = [UIColor redColor];
        self.statusLabel.text = @"未检测到场地线";
    }

    // Update layer paths with animation
    [self updateLayer:self.horizontalLineLayer withPath:horizontalPath];
    [self updateLayer:self.verticalLineLayer withPath:verticalPath];
    [self updateLayer:self.arcLineLayer withPath:arcPath];
}

- (UIBezierPath *)transformPath:(UIBezierPath *)normalizedPath
                      viewWidth:(CGFloat)viewWidth
                     viewHeight:(CGFloat)viewHeight {

    // Vision normalized coordinates: (0,0) is bottom-left, (1,1) is top-right
    // Camera is landscape, displayed in portrait, so we need rotation
    CGAffineTransform transform = CGAffineTransformIdentity;

    // Scale to view size (swap width/height for rotation)
    transform = CGAffineTransformScale(transform, viewHeight, viewWidth);

    // Rotate 90 degrees clockwise and translate
    transform = CGAffineTransformRotate(transform, M_PI_2);
    transform = CGAffineTransformTranslate(transform, 0, -1);

    UIBezierPath *transformedPath = [normalizedPath copy];
    [transformedPath applyTransform:transform];

    return transformedPath;
}

- (void)updateLayer:(CAShapeLayer *)layer withPath:(UIBezierPath *)path {
    // Smooth transition animation
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"path"];
    animation.fromValue = (__bridge id)layer.path;
    animation.toValue = (__bridge id)path.CGPath;
    animation.duration = 0.15;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];

    layer.path = path.CGPath;
    [layer addAnimation:animation forKey:@"pathAnimation"];
}

- (void)courtLineDetectionFailed:(NSString *)reason {
    self.statusLabel.text = reason;
    self.lineCountLabel.textColor = [UIColor redColor];
    [self clearLineLayers];
}

@end
