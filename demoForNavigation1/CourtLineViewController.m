//
//  CourtLineViewController.m
//  demoForNavigation1
//
//  View controller for basketball court line detection
//  Includes manual calibration mode with draggable corner points
//

#import "CourtLineViewController.h"
#import "CourtLineDetector.h"
#import <AVFoundation/AVFoundation.h>

// Corner handle size
static const CGFloat kHandleSize = 44.0;

@interface CourtLineViewController () <AVCaptureVideoDataOutputSampleBufferDelegate, CourtLineDetectorDelegate>

// Camera
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) dispatch_queue_t videoQueue;

// Detector
@property (nonatomic, strong) CourtLineDetector *detector;

// Court overlay layer
@property (nonatomic, strong) CAShapeLayer *courtLayer;
@property (nonatomic, strong) CAShapeLayer *calibrationLayer;  // For calibration overlay

// UI Elements
@property (nonatomic, strong) UIView *cameraContainerView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *scoreLabel;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIButton *calibrateButton;

// Calibration handles (4 corners: TL, TR, BR, BL)
@property (nonatomic, strong) UIView *handleTopLeft;
@property (nonatomic, strong) UIView *handleTopRight;
@property (nonatomic, strong) UIView *handleBottomRight;
@property (nonatomic, strong) UIView *handleBottomLeft;

// State
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) BOOL isCalibrating;
@property (nonatomic, assign) BOOL isCalibrated;

// Calibrated court corners (normalized 0-1)
@property (nonatomic, assign) CGPoint calibratedTL;
@property (nonatomic, assign) CGPoint calibratedTR;
@property (nonatomic, assign) CGPoint calibratedBR;
@property (nonatomic, assign) CGPoint calibratedBL;

@end

@implementation CourtLineViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"场地线识别";
    self.view.backgroundColor = [UIColor blackColor];
    self.isRunning = NO;
    self.isCalibrating = NO;
    self.isCalibrated = NO;

    // Default court corners (centered rectangle)
    [self resetCalibrationToDefault];

    [self setupDetector];
    [self setupUI];
    [self setupCourtLayers];
    [self setupCalibrationHandles];
    [self checkCameraPermission];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Debug: verify button exists and is visible
    NSLog(@"Calibrate button: %@, frame: %@, hidden: %d, alpha: %f, superview: %@",
          self.calibrateButton,
          NSStringFromCGRect(self.calibrateButton.frame),
          self.calibrateButton.hidden,
          self.calibrateButton.alpha,
          self.calibrateButton.superview);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopCamera];
}

- (void)dealloc {
    [self stopCamera];
}

#pragma mark - Default Calibration

- (void)resetCalibrationToDefault {
    // Default: centered court taking 60% of view
    CGFloat margin = 0.2;
    self.calibratedTL = CGPointMake(margin, margin);
    self.calibratedTR = CGPointMake(1.0 - margin, margin);
    self.calibratedBR = CGPointMake(1.0 - margin, 1.0 - margin);
    self.calibratedBL = CGPointMake(margin, 1.0 - margin);
}

#pragma mark - Setup

- (void)setupDetector {
    self.detector = [[CourtLineDetector alloc] init];
    self.detector.delegate = self;
    self.detector.edgeThreshold = 0.02;
    self.detector.minMatchScore = 0.3;
}

- (void)setupCourtLayers {
    // Main court lines (cyan) - for auto detection
    self.courtLayer = [CAShapeLayer layer];
    self.courtLayer.strokeColor = [UIColor cyanColor].CGColor;
    self.courtLayer.fillColor = [UIColor clearColor].CGColor;
    self.courtLayer.lineWidth = 2.5;
    self.courtLayer.lineCap = kCALineCapRound;

    // Calibration overlay (green) - for manual calibration
    self.calibrationLayer = [CAShapeLayer layer];
    self.calibrationLayer.strokeColor = [UIColor greenColor].CGColor;
    self.calibrationLayer.fillColor = [[UIColor greenColor] colorWithAlphaComponent:0.1].CGColor;
    self.calibrationLayer.lineWidth = 3.0;
    self.calibrationLayer.lineDashPattern = @[@8, @4];
    self.calibrationLayer.hidden = YES;
}

- (void)setupCalibrationHandles {
    // Create 4 corner handles
    self.handleTopLeft = [self createHandleWithColor:[UIColor redColor]];
    self.handleTopRight = [self createHandleWithColor:[UIColor greenColor]];
    self.handleBottomRight = [self createHandleWithColor:[UIColor blueColor]];
    self.handleBottomLeft = [self createHandleWithColor:[UIColor yellowColor]];

    // Add to camera container
    [self.cameraContainerView addSubview:self.handleTopLeft];
    [self.cameraContainerView addSubview:self.handleTopRight];
    [self.cameraContainerView addSubview:self.handleBottomRight];
    [self.cameraContainerView addSubview:self.handleBottomLeft];

    // Initially hidden
    [self setHandlesHidden:YES];
}

- (UIView *)createHandleWithColor:(UIColor *)color {
    UIView *handle = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kHandleSize, kHandleSize)];
    handle.backgroundColor = [color colorWithAlphaComponent:0.7];
    handle.layer.cornerRadius = kHandleSize / 2;
    handle.layer.borderWidth = 3;
    handle.layer.borderColor = [UIColor whiteColor].CGColor;

    // Add center dot
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(kHandleSize/2 - 4, kHandleSize/2 - 4, 8, 8)];
    dot.backgroundColor = [UIColor whiteColor];
    dot.layer.cornerRadius = 4;
    [handle addSubview:dot];

    // Add pan gesture
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [handle addGestureRecognizer:pan];
    handle.userInteractionEnabled = YES;

    return handle;
}

- (void)setHandlesHidden:(BOOL)hidden {
    self.handleTopLeft.hidden = hidden;
    self.handleTopRight.hidden = hidden;
    self.handleBottomRight.hidden = hidden;
    self.handleBottomLeft.hidden = hidden;
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
    self.statusLabel.font = [UIFont boldSystemFontOfSize:18];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];

    // Score label
    self.scoreLabel = [[UILabel alloc] init];
    self.scoreLabel.text = @"拖动角点校准球场位置";
    self.scoreLabel.textColor = [UIColor lightGrayColor];
    self.scoreLabel.textAlignment = NSTextAlignmentCenter;
    self.scoreLabel.font = [UIFont systemFontOfSize:14];
    self.scoreLabel.numberOfLines = 2;
    self.scoreLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scoreLabel];

    // Calibrate button
    self.calibrateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.calibrateButton setTitle:@"手动校准" forState:UIControlStateNormal];
    [self.calibrateButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.calibrateButton.backgroundColor = [UIColor colorWithRed:0.6 green:0.4 blue:0.8 alpha:1.0];
    self.calibrateButton.layer.cornerRadius = 25;
    self.calibrateButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.calibrateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.calibrateButton addTarget:self action:@selector(toggleCalibration) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.calibrateButton];

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
        // Camera container - use 1:1 aspect ratio to leave more room for buttons
        [self.cameraContainerView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [self.cameraContainerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.cameraContainerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.cameraContainerView.heightAnchor constraintEqualToAnchor:self.cameraContainerView.widthAnchor multiplier:1.0],

        // Status label
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.cameraContainerView.bottomAnchor constant:10],
        [self.statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        // Score label
        [self.scoreLabel.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:4],
        [self.scoreLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.scoreLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        // Buttons side by side at bottom
        [self.calibrateButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-15],
        [self.calibrateButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.calibrateButton.widthAnchor constraintEqualToConstant:130],
        [self.calibrateButton.heightAnchor constraintEqualToConstant:50],

        [self.startButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-15],
        [self.startButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.startButton.widthAnchor constraintEqualToConstant:130],
        [self.startButton.heightAnchor constraintEqualToConstant:50],
    ]];
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
                                                                   message:@"请在设置中允许访问相机"
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

    // Add overlay layers
    [self.cameraContainerView.layer addSublayer:self.courtLayer];
    [self.cameraContainerView.layer addSublayer:self.calibrationLayer];

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
    CGRect bounds = self.cameraContainerView.bounds;
    self.previewLayer.frame = bounds;
    self.courtLayer.frame = bounds;
    self.calibrationLayer.frame = bounds;

    // Update handle positions
    [self updateHandlePositions];
    [self updateCalibrationOverlay];
}

#pragma mark - Handle Positions

- (void)updateHandlePositions {
    CGRect bounds = self.cameraContainerView.bounds;

    self.handleTopLeft.center = CGPointMake(self.calibratedTL.x * bounds.size.width,
                                             self.calibratedTL.y * bounds.size.height);
    self.handleTopRight.center = CGPointMake(self.calibratedTR.x * bounds.size.width,
                                              self.calibratedTR.y * bounds.size.height);
    self.handleBottomRight.center = CGPointMake(self.calibratedBR.x * bounds.size.width,
                                                 self.calibratedBR.y * bounds.size.height);
    self.handleBottomLeft.center = CGPointMake(self.calibratedBL.x * bounds.size.width,
                                                self.calibratedBL.y * bounds.size.height);
}

- (void)updateCalibrationOverlay {
    CGRect bounds = self.cameraContainerView.bounds;

    UIBezierPath *path = [UIBezierPath bezierPath];

    CGPoint tl = CGPointMake(self.calibratedTL.x * bounds.size.width, self.calibratedTL.y * bounds.size.height);
    CGPoint tr = CGPointMake(self.calibratedTR.x * bounds.size.width, self.calibratedTR.y * bounds.size.height);
    CGPoint br = CGPointMake(self.calibratedBR.x * bounds.size.width, self.calibratedBR.y * bounds.size.height);
    CGPoint bl = CGPointMake(self.calibratedBL.x * bounds.size.width, self.calibratedBL.y * bounds.size.height);

    // Draw quadrilateral
    [path moveToPoint:tl];
    [path addLineToPoint:tr];
    [path addLineToPoint:br];
    [path addLineToPoint:bl];
    [path closePath];

    // Draw diagonals
    [path moveToPoint:tl];
    [path addLineToPoint:br];
    [path moveToPoint:tr];
    [path addLineToPoint:bl];

    // Draw midlines
    CGPoint midTop = CGPointMake((tl.x + tr.x) / 2, (tl.y + tr.y) / 2);
    CGPoint midBottom = CGPointMake((bl.x + br.x) / 2, (bl.y + br.y) / 2);
    CGPoint midLeft = CGPointMake((tl.x + bl.x) / 2, (tl.y + bl.y) / 2);
    CGPoint midRight = CGPointMake((tr.x + br.x) / 2, (tr.y + br.y) / 2);

    [path moveToPoint:midTop];
    [path addLineToPoint:midBottom];
    [path moveToPoint:midLeft];
    [path addLineToPoint:midRight];

    self.calibrationLayer.path = path.CGPath;
}

#pragma mark - Gesture Handling

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *handle = gesture.view;
    CGPoint translation = [gesture translationInView:self.cameraContainerView];
    CGRect bounds = self.cameraContainerView.bounds;

    // Calculate new center
    CGPoint newCenter = CGPointMake(handle.center.x + translation.x,
                                     handle.center.y + translation.y);

    // Clamp to bounds
    newCenter.x = MAX(kHandleSize/2, MIN(bounds.size.width - kHandleSize/2, newCenter.x));
    newCenter.y = MAX(kHandleSize/2, MIN(bounds.size.height - kHandleSize/2, newCenter.y));

    handle.center = newCenter;
    [gesture setTranslation:CGPointZero inView:self.cameraContainerView];

    // Update normalized coordinates
    CGPoint normalized = CGPointMake(newCenter.x / bounds.size.width,
                                      newCenter.y / bounds.size.height);

    if (handle == self.handleTopLeft) {
        self.calibratedTL = normalized;
    } else if (handle == self.handleTopRight) {
        self.calibratedTR = normalized;
    } else if (handle == self.handleBottomRight) {
        self.calibratedBR = normalized;
    } else if (handle == self.handleBottomLeft) {
        self.calibratedBL = normalized;
    }

    // Update overlay
    [self updateCalibrationOverlay];

    // Haptic feedback on begin
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feedback impactOccurred];
    }
}

#pragma mark - Actions

- (void)toggleCalibration {
    self.isCalibrating = !self.isCalibrating;

    if (self.isCalibrating) {
        // Enter calibration mode
        [self.calibrateButton setTitle:@"完成校准" forState:UIControlStateNormal];
        self.calibrateButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:1.0];

        // Stop detection if running
        if (self.isRunning) {
            [self toggleDetection];
        }
        self.startButton.enabled = NO;
        self.startButton.alpha = 0.5;

        // Show handles and overlay
        [self setHandlesHidden:NO];
        self.calibrationLayer.hidden = NO;
        self.courtLayer.hidden = YES;

        self.statusLabel.text = @"校准模式";
        self.statusLabel.textColor = [UIColor greenColor];
        self.scoreLabel.text = @"拖动四个角点对齐球场边界";

        [self updateHandlePositions];
        [self updateCalibrationOverlay];

    } else {
        // Exit calibration mode
        [self.calibrateButton setTitle:@"手动校准" forState:UIControlStateNormal];
        self.calibrateButton.backgroundColor = [UIColor colorWithRed:0.6 green:0.4 blue:0.8 alpha:1.0];

        self.startButton.enabled = YES;
        self.startButton.alpha = 1.0;

        // Hide handles, keep overlay briefly then hide
        [self setHandlesHidden:YES];

        self.isCalibrated = YES;
        self.statusLabel.text = @"校准完成";
        self.statusLabel.textColor = [UIColor cyanColor];
        self.scoreLabel.text = @"点击\"开始检测\"使用校准后的区域";

        // Keep calibration overlay visible but change style
        self.calibrationLayer.strokeColor = [UIColor cyanColor].CGColor;
        self.calibrationLayer.fillColor = [[UIColor cyanColor] colorWithAlphaComponent:0.05].CGColor;
        self.calibrationLayer.lineDashPattern = nil;
        self.calibrationLayer.lineWidth = 2.0;
    }
}

- (void)toggleDetection {
    if (self.isRunning) {
        [self.detector stopDetection];
        self.isRunning = NO;
        [self.startButton setTitle:@"开始检测" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:0.9 alpha:1.0];
        self.statusLabel.text = @"已暂停";
        self.statusLabel.textColor = [UIColor whiteColor];
        self.courtLayer.path = nil;
    } else {
        [self.detector startDetection];
        self.isRunning = YES;
        [self.startButton setTitle:@"停止检测" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:1.0];
        self.statusLabel.text = @"检测中...";
        self.statusLabel.textColor = [UIColor yellowColor];

        // Hide calibration overlay during detection
        self.calibrationLayer.hidden = YES;
        self.courtLayer.hidden = NO;
    }
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (pixelBuffer) {
        [self.detector processPixelBuffer:pixelBuffer];
    }
}

#pragma mark - CourtLineDetectorDelegate

- (void)courtLineDetector:(id)detector didDetectResult:(CourtDetectionResult *)result {
    if (self.isCalibrated) {
        // Use calibrated court position
        [self drawCalibratedCourt];
        self.scoreLabel.text = @"使用校准后的球场区域";

        if (result.courtFound) {
            self.statusLabel.text = @"检测到球场";
            self.statusLabel.textColor = [UIColor greenColor];
        }
    } else {
        // Use auto-detected lines
        if (result.bestPose) {
            CGFloat scorePercent = result.bestPose.matchScore * 100;
            self.scoreLabel.text = [NSString stringWithFormat:@"自动匹配度: %.1f%%", scorePercent];
        }

        if (result.courtFound) {
            self.statusLabel.text = @"检测到球场";
            self.statusLabel.textColor = [UIColor greenColor];
        } else {
            self.statusLabel.text = @"匹配中...";
            self.statusLabel.textColor = [UIColor yellowColor];
        }

        [self drawProjectedLines:result.projectedLines courtFound:result.courtFound];
    }
}

- (void)drawCalibratedCourt {
    CGRect bounds = self.cameraContainerView.bounds;

    CGPoint tl = CGPointMake(self.calibratedTL.x * bounds.size.width, self.calibratedTL.y * bounds.size.height);
    CGPoint tr = CGPointMake(self.calibratedTR.x * bounds.size.width, self.calibratedTR.y * bounds.size.height);
    CGPoint br = CGPointMake(self.calibratedBR.x * bounds.size.width, self.calibratedBR.y * bounds.size.height);
    CGPoint bl = CGPointMake(self.calibratedBL.x * bounds.size.width, self.calibratedBL.y * bounds.size.height);

    UIBezierPath *path = [UIBezierPath bezierPath];

    // Draw boundary
    [path moveToPoint:tl];
    [path addLineToPoint:tr];
    [path addLineToPoint:br];
    [path addLineToPoint:bl];
    [path closePath];

    // Draw FIBA court lines inside the calibrated area

    // Center line (horizontal midline)
    CGPoint midLeft = CGPointMake((tl.x + bl.x) / 2, (tl.y + bl.y) / 2);
    CGPoint midRight = CGPointMake((tr.x + br.x) / 2, (tr.y + br.y) / 2);
    [path moveToPoint:midLeft];
    [path addLineToPoint:midRight];

    // Free throw line (41.4% from baseline)
    CGFloat ftRatio = 0.414;
    CGPoint ftLeft = CGPointMake(bl.x + (tl.x - bl.x) * ftRatio, bl.y + (tl.y - bl.y) * ftRatio);
    CGPoint ftRight = CGPointMake(br.x + (tr.x - br.x) * ftRatio, br.y + (tr.y - br.y) * ftRatio);

    // Lane lines (16.3% from center on each side)
    CGFloat laneRatio = 0.163;
    CGPoint laneLeftBottom = [self interpolateFrom:bl to:br ratio:0.5 - laneRatio];
    CGPoint laneLeftTop = [self interpolateFrom:ftLeft to:ftRight ratio:0.5 - laneRatio];
    CGPoint laneRightBottom = [self interpolateFrom:bl to:br ratio:0.5 + laneRatio];
    CGPoint laneRightTop = [self interpolateFrom:ftLeft to:ftRight ratio:0.5 + laneRatio];

    // Free throw line (just the lane width)
    [path moveToPoint:laneLeftTop];
    [path addLineToPoint:laneRightTop];

    // Lane lines
    [path moveToPoint:laneLeftBottom];
    [path addLineToPoint:laneLeftTop];
    [path moveToPoint:laneRightBottom];
    [path addLineToPoint:laneRightTop];

    self.courtLayer.path = path.CGPath;
    self.courtLayer.strokeColor = [UIColor cyanColor].CGColor;
    self.courtLayer.fillColor = [UIColor clearColor].CGColor;
}

- (CGPoint)interpolateFrom:(CGPoint)p1 to:(CGPoint)p2 ratio:(CGFloat)ratio {
    return CGPointMake(p1.x + (p2.x - p1.x) * ratio,
                       p1.y + (p2.y - p1.y) * ratio);
}

- (void)drawProjectedLines:(NSArray<ProjectedLine *> *)projectedLines courtFound:(BOOL)courtFound {
    CGRect bounds = self.cameraContainerView.bounds;
    CGFloat viewWidth = bounds.size.width;
    CGFloat viewHeight = bounds.size.height;

    UIBezierPath *path = [UIBezierPath bezierPath];

    for (ProjectedLine *line in projectedLines) {
        if (!line.isVisible) continue;

        CGFloat startX = line.start.x * viewWidth;
        CGFloat startY = (1.0 - line.start.y) * viewHeight;
        CGFloat endX = line.end.x * viewWidth;
        CGFloat endY = (1.0 - line.end.y) * viewHeight;

        [path moveToPoint:CGPointMake(startX, startY)];
        [path addLineToPoint:CGPointMake(endX, endY)];
    }

    self.courtLayer.opacity = courtFound ? 1.0 : 0.5;
    self.courtLayer.path = path.CGPath;
}

- (void)courtLineDetectorDidFail:(id)detector withError:(NSString *)error {
    self.statusLabel.text = error;
    self.statusLabel.textColor = [UIColor redColor];
    self.courtLayer.path = nil;
}

@end
