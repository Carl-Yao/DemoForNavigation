//
//  CourtLineViewController.m
//  demoForNavigation1
//
//  View controller for basketball court line detection
//  Displays FIBA template matched to detected edges
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

// Court overlay layer
@property (nonatomic, strong) CAShapeLayer *courtLayer;      // Main court lines
@property (nonatomic, strong) CAShapeLayer *threePointLayer; // Three-point arc

// UI Elements
@property (nonatomic, strong) UIView *cameraContainerView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *scoreLabel;
@property (nonatomic, strong) UILabel *poseLabel;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UISlider *sensitivitySlider;
@property (nonatomic, strong) UILabel *sensitivityLabel;

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
    [self setupCourtLayers];
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
    self.detector.edgeThreshold = 1.5;
    self.detector.minMatchScore = 0.15;
}

- (void)setupCourtLayers {
    // Main court lines (cyan)
    self.courtLayer = [CAShapeLayer layer];
    self.courtLayer.strokeColor = [UIColor cyanColor].CGColor;
    self.courtLayer.fillColor = [UIColor clearColor].CGColor;
    self.courtLayer.lineWidth = 2.5;
    self.courtLayer.lineCap = kCALineCapRound;

    // Three-point arc (yellow)
    self.threePointLayer = [CAShapeLayer layer];
    self.threePointLayer.strokeColor = [UIColor yellowColor].CGColor;
    self.threePointLayer.fillColor = [UIColor clearColor].CGColor;
    self.threePointLayer.lineWidth = 2.5;
    self.threePointLayer.lineCap = kCALineCapRound;
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
    self.scoreLabel.text = @"匹配度: --";
    self.scoreLabel.textColor = [UIColor lightGrayColor];
    self.scoreLabel.textAlignment = NSTextAlignmentCenter;
    self.scoreLabel.font = [UIFont systemFontOfSize:14];
    self.scoreLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.scoreLabel];

    // Pose label (debug info)
    self.poseLabel = [[UILabel alloc] init];
    self.poseLabel.text = @"";
    self.poseLabel.textColor = [UIColor grayColor];
    self.poseLabel.textAlignment = NSTextAlignmentCenter;
    self.poseLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.poseLabel.numberOfLines = 2;
    self.poseLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.poseLabel];

    // Legend
    UILabel *legendLabel = [[UILabel alloc] init];
    legendLabel.text = @"青色: 边界线  黄色: 罚球线/禁区线";
    legendLabel.textColor = [UIColor lightGrayColor];
    legendLabel.textAlignment = NSTextAlignmentCenter;
    legendLabel.font = [UIFont systemFontOfSize:12];
    legendLabel.translatesAutoresizingMaskIntoConstraints = NO;
    legendLabel.tag = 100;
    [self.view addSubview:legendLabel];

    // Sensitivity slider label
    self.sensitivityLabel = [[UILabel alloc] init];
    self.sensitivityLabel.text = @"灵敏度: 1.5";
    self.sensitivityLabel.textColor = [UIColor lightGrayColor];
    self.sensitivityLabel.font = [UIFont systemFontOfSize:14];
    self.sensitivityLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.sensitivityLabel];

    // Sensitivity slider
    self.sensitivitySlider = [[UISlider alloc] init];
    self.sensitivitySlider.minimumValue = 0.5;
    self.sensitivitySlider.maximumValue = 3.0;
    self.sensitivitySlider.value = 1.5;
    self.sensitivitySlider.tintColor = [UIColor cyanColor];
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

    UILabel *legend = (UILabel *)[self.view viewWithTag:100];

    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // Camera container - taller for portrait phone shooting
        [self.cameraContainerView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [self.cameraContainerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.cameraContainerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.cameraContainerView.heightAnchor constraintEqualToAnchor:self.cameraContainerView.widthAnchor multiplier:4.0/3.0],

        // Status label
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.cameraContainerView.bottomAnchor constant:12],
        [self.statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        // Score label
        [self.scoreLabel.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:4],
        [self.scoreLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        // Pose label
        [self.poseLabel.topAnchor constraintEqualToAnchor:self.scoreLabel.bottomAnchor constant:4],
        [self.poseLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.poseLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        // Legend
        [legend.topAnchor constraintEqualToAnchor:self.poseLabel.bottomAnchor constant:10],
        [legend.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        // Sensitivity label
        [self.sensitivityLabel.topAnchor constraintEqualToAnchor:legend.bottomAnchor constant:15],
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

    // Add court layers on top
    [self.cameraContainerView.layer addSublayer:self.courtLayer];
    [self.cameraContainerView.layer addSublayer:self.threePointLayer];

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
    self.threePointLayer.frame = bounds;
}

#pragma mark - Actions

- (void)toggleDetection {
    if (self.isRunning) {
        [self.detector stopDetection];
        self.isRunning = NO;
        [self.startButton setTitle:@"开始检测" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:0.9 alpha:1.0];
        self.statusLabel.text = @"已暂停";
        [self clearCourtLayers];
    } else {
        [self.detector startDetection];
        self.isRunning = YES;
        [self.startButton setTitle:@"停止检测" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:1.0];
        self.statusLabel.text = @"检测中...";
    }
}

- (void)sensitivityChanged:(UISlider *)slider {
    self.detector.edgeThreshold = slider.value;
    self.sensitivityLabel.text = [NSString stringWithFormat:@"灵敏度: %.1f", slider.value];
}

- (void)clearCourtLayers {
    self.courtLayer.path = nil;
    self.threePointLayer.path = nil;
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
    // Update score display
    if (result.bestPose) {
        CGFloat scorePercent = result.bestPose.matchScore * 100;
        self.scoreLabel.text = [NSString stringWithFormat:@"匹配度: %.1f%%", scorePercent];

        // Show pose debug info
        self.poseLabel.text = [NSString stringWithFormat:@"位置:(%.2f,%.2f) 旋转:%.0f° 缩放:%.2f 透视:%.2f",
                               result.bestPose.centerX, result.bestPose.centerY,
                               result.bestPose.rotation, result.bestPose.scale,
                               result.bestPose.perspectiveY];
    }

    // Update status
    if (result.courtFound) {
        self.statusLabel.text = @"检测到球场";
        self.statusLabel.textColor = [UIColor greenColor];
    } else {
        self.statusLabel.text = @"匹配中...";
        self.statusLabel.textColor = [UIColor yellowColor];
    }

    // Draw projected court lines
    [self drawProjectedLines:result.projectedLines courtFound:result.courtFound];
}

- (void)drawProjectedLines:(NSArray<ProjectedLine *> *)projectedLines courtFound:(BOOL)courtFound {
    CGRect bounds = self.cameraContainerView.bounds;
    CGFloat viewWidth = bounds.size.width;
    CGFloat viewHeight = bounds.size.height;

    UIBezierPath *courtPath = [UIBezierPath bezierPath];      // Boundary lines (cyan)
    UIBezierPath *interiorPath = [UIBezierPath bezierPath];   // Interior lines (yellow)

    for (ProjectedLine *line in projectedLines) {
        if (!line.isVisible) continue;

        // Convert normalized coords to view coords (flip Y for screen coordinates)
        CGFloat startX = line.start.x * viewWidth;
        CGFloat startY = (1.0 - line.start.y) * viewHeight;
        CGFloat endX = line.end.x * viewWidth;
        CGFloat endY = (1.0 - line.end.y) * viewHeight;

        UIBezierPath *linePath = [UIBezierPath bezierPath];
        [linePath moveToPoint:CGPointMake(startX, startY)];
        [linePath addLineToPoint:CGPointMake(endX, endY)];

        // Route to appropriate layer based on line name
        // Boundary lines: baseline, midcourt, sideline_left, sideline_right
        // Interior lines: freethrow, lane
        if ([line.name hasPrefix:@"baseline"] ||
            [line.name hasPrefix:@"midcourt"] ||
            [line.name hasPrefix:@"sideline"]) {
            [courtPath appendPath:linePath];
        } else if ([line.name hasPrefix:@"freethrow"] ||
                   [line.name hasPrefix:@"lane"]) {
            [interiorPath appendPath:linePath];
        } else {
            // Unclassified lines (horizontal/vertical) - show in low opacity
            [courtPath appendPath:linePath];
        }
    }

    // Update layers with opacity based on match confidence
    CGFloat opacity = courtFound ? 1.0 : 0.4;
    self.courtLayer.opacity = opacity;
    self.threePointLayer.opacity = courtFound ? 1.0 : 0.3;

    self.courtLayer.path = courtPath.CGPath;
    self.threePointLayer.path = interiorPath.CGPath;
}

- (void)courtLineDetectorDidFail:(id)detector withError:(NSString *)error {
    self.statusLabel.text = error;
    self.statusLabel.textColor = [UIColor redColor];
    [self clearCourtLayers];
}

@end
