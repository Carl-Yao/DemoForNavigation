//
//  ShootingViewController.m
//  demoForNavigation1
//
//  View controller for basketball shooting detection with camera
//

#import "ShootingViewController.h"
#import "ShootingDetector.h"
#import <AVFoundation/AVFoundation.h>

@interface ShootingViewController () <AVCaptureVideoDataOutputSampleBufferDelegate, ShootingDetectorDelegate>

// Camera
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) dispatch_queue_t videoQueue;

// Detector
@property (nonatomic, strong) ShootingDetector *detector;

// UI Elements
@property (nonatomic, strong) UILabel *shotCountLabel;
@property (nonatomic, strong) UILabel *phaseLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIButton *resetButton;
@property (nonatomic, strong) UIView *poseIndicatorView;
@property (nonatomic, strong) UILabel *instructionLabel;

// Pose visualization layers
@property (nonatomic, strong) CAShapeLayer *poseLayer;

@property (nonatomic, assign) BOOL isRunning;

@end

@implementation ShootingViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"投篮检测";
    self.view.backgroundColor = [UIColor blackColor];
    self.isRunning = NO;

    [self setupDetector];
    [self setupUI];
    [self setupPoseLayer];
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
    self.detector = [[ShootingDetector alloc] init];
    self.detector.delegate = self;
    self.detector.raiseThreshold = 0.15;
    self.detector.releaseThreshold = 0.08;
}

- (void)setupUI {
    // Instruction label at top
    self.instructionLabel = [[UILabel alloc] init];
    self.instructionLabel.text = @"将手机对准投篮的人\n确保上半身在画面中";
    self.instructionLabel.textColor = [UIColor whiteColor];
    self.instructionLabel.textAlignment = NSTextAlignmentCenter;
    self.instructionLabel.numberOfLines = 2;
    self.instructionLabel.font = [UIFont systemFontOfSize:16];
    self.instructionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.instructionLabel];

    // Shot count label
    self.shotCountLabel = [[UILabel alloc] init];
    self.shotCountLabel.text = @"0";
    self.shotCountLabel.textColor = [UIColor whiteColor];
    self.shotCountLabel.textAlignment = NSTextAlignmentCenter;
    self.shotCountLabel.font = [UIFont boldSystemFontOfSize:100];
    self.shotCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.shotCountLabel];

    // Phase label
    self.phaseLabel = [[UILabel alloc] init];
    self.phaseLabel.text = @"等待投篮动作";
    self.phaseLabel.textColor = [UIColor lightGrayColor];
    self.phaseLabel.textAlignment = NSTextAlignmentCenter;
    self.phaseLabel.font = [UIFont systemFontOfSize:20];
    self.phaseLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.phaseLabel];

    // Status label
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"准备就绪";
    self.statusLabel.textColor = [UIColor grayColor];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];

    // Pose indicator view
    self.poseIndicatorView = [[UIView alloc] init];
    self.poseIndicatorView.backgroundColor = [UIColor grayColor];
    self.poseIndicatorView.layer.cornerRadius = 15;
    self.poseIndicatorView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.poseIndicatorView];

    // Start/Stop button
    self.startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.startButton setTitle:@"开始检测" forState:UIControlStateNormal];
    [self.startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.startButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.4 blue:0.0 alpha:1.0];
    self.startButton.layer.cornerRadius = 25;
    self.startButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.startButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.startButton addTarget:self action:@selector(toggleDetection) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.startButton];

    // Reset button
    self.resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.resetButton setTitle:@"重置" forState:UIControlStateNormal];
    [self.resetButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.resetButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1.0];
    self.resetButton.layer.cornerRadius = 25;
    self.resetButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.resetButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.resetButton addTarget:self action:@selector(resetCount) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.resetButton];

    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // Instruction label
        [self.instructionLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
        [self.instructionLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.instructionLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        // Shot count
        [self.shotCountLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.shotCountLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-60],

        // Phase label
        [self.phaseLabel.topAnchor constraintEqualToAnchor:self.shotCountLabel.bottomAnchor constant:5],
        [self.phaseLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        // Status label
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.phaseLabel.bottomAnchor constant:10],
        [self.statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        // Pose indicator
        [self.poseIndicatorView.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:20],
        [self.poseIndicatorView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.poseIndicatorView.widthAnchor constraintEqualToConstant:30],
        [self.poseIndicatorView.heightAnchor constraintEqualToConstant:30],

        // Start button
        [self.startButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-30],
        [self.startButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:40],
        [self.startButton.heightAnchor constraintEqualToConstant:50],
        [self.startButton.trailingAnchor constraintEqualToAnchor:self.view.centerXAnchor constant:-10],

        // Reset button
        [self.resetButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-30],
        [self.resetButton.leadingAnchor constraintEqualToAnchor:self.view.centerXAnchor constant:10],
        [self.resetButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-40],
        [self.resetButton.heightAnchor constraintEqualToConstant:50],
    ]];
}

- (void)setupPoseLayer {
    self.poseLayer = [CAShapeLayer layer];
    self.poseLayer.strokeColor = [UIColor greenColor].CGColor;
    self.poseLayer.fillColor = [UIColor clearColor].CGColor;
    self.poseLayer.lineWidth = 3.0;
    self.poseLayer.lineCap = kCALineCapRound;
}

#pragma mark - Camera Setup

- (void)checkCameraPermission {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];

    switch (status) {
        case AVAuthorizationStatusAuthorized:
            [self setupCamera];
            break;
        case AVAuthorizationStatusNotDetermined:
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
        default:
            [self showCameraPermissionAlert];
            break;
    }
}

- (void)showCameraPermissionAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"需要相机权限"
                                                                   message:@"请在设置中允许访问相机以使用投篮检测功能"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];

    self.statusLabel.text = @"需要相机权限";
}

- (void)setupCamera {
    self.captureSession = [[AVCaptureSession alloc] init];
    self.captureSession.sessionPreset = AVCaptureSessionPreset640x480;

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

    self.videoQueue = dispatch_queue_create("com.demo.shootingQueue", DISPATCH_QUEUE_SERIAL);
    [videoOutput setSampleBufferDelegate:self queue:self.videoQueue];

    if ([self.captureSession canAddOutput:videoOutput]) {
        [self.captureSession addOutput:videoOutput];
    }

    // Preview layer
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.previewLayer.frame = self.view.bounds;
    self.previewLayer.opacity = 0.3;
    [self.view.layer insertSublayer:self.previewLayer atIndex:0];

    // Add pose layer
    [self.view.layer addSublayer:self.poseLayer];

    // Start session on background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self.captureSession startRunning];
    });
}

- (void)stopCamera {
    if (self.captureSession.isRunning) {
        [self.captureSession stopRunning];
    }
    [self.detector stopDetection];
}

#pragma mark - Actions

- (void)toggleDetection {
    if (self.isRunning) {
        [self.detector stopDetection];
        self.isRunning = NO;
        [self.startButton setTitle:@"开始检测" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.4 blue:0.0 alpha:1.0];
        self.statusLabel.text = @"已暂停";
        self.phaseLabel.text = @"等待投篮动作";
    } else {
        [self.detector startDetection];
        self.isRunning = YES;
        [self.startButton setTitle:@"暂停" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:0.6 green:0.0 blue:0.0 alpha:1.0];
        self.statusLabel.text = @"检测中...";
    }
}

- (void)resetCount {
    [self.detector resetShotCount];
    self.shotCountLabel.text = @"0";
    self.phaseLabel.text = @"等待投篮动作";
    self.poseIndicatorView.backgroundColor = [UIColor grayColor];
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {

    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (pixelBuffer) {
        [self.detector processPixelBuffer:pixelBuffer];
    }
}

#pragma mark - ShootingDetectorDelegate

- (void)shootingDetected:(NSInteger)shotCount {
    self.shotCountLabel.text = [NSString stringWithFormat:@"%ld", (long)shotCount];

    // Flash indicator orange on shot
    self.poseIndicatorView.backgroundColor = [UIColor orangeColor];

    // Animate count label
    [UIView animateWithDuration:0.15 animations:^{
        self.shotCountLabel.transform = CGAffineTransformMakeScale(1.3, 1.3);
        self.shotCountLabel.textColor = [UIColor orangeColor];
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.15 animations:^{
            self.shotCountLabel.transform = CGAffineTransformIdentity;
            self.shotCountLabel.textColor = [UIColor whiteColor];
        }];
    }];
}

- (void)shootingPhaseChanged:(ShootingPhase)phase {
    switch (phase) {
        case ShootingPhaseIdle:
            self.phaseLabel.text = @"等待投篮动作";
            self.phaseLabel.textColor = [UIColor lightGrayColor];
            self.poseIndicatorView.backgroundColor = [UIColor grayColor];
            break;
        case ShootingPhaseReady:
            self.phaseLabel.text = @"准备姿势";
            self.phaseLabel.textColor = [UIColor yellowColor];
            self.poseIndicatorView.backgroundColor = [UIColor yellowColor];
            break;
        case ShootingPhaseRaising:
            self.phaseLabel.text = @"举球中...";
            self.phaseLabel.textColor = [UIColor cyanColor];
            self.poseIndicatorView.backgroundColor = [UIColor cyanColor];
            break;
        case ShootingPhaseRelease:
            self.phaseLabel.text = @"出手!";
            self.phaseLabel.textColor = [UIColor orangeColor];
            self.poseIndicatorView.backgroundColor = [UIColor orangeColor];
            break;
        case ShootingPhaseFollowThrough:
            self.phaseLabel.text = @"跟随动作";
            self.phaseLabel.textColor = [UIColor greenColor];
            self.poseIndicatorView.backgroundColor = [UIColor greenColor];
            break;
    }
}

- (void)poseUpdatedWithRightWrist:(CGPoint)rightWrist
                      rightElbow:(CGPoint)rightElbow
                    rightShoulder:(CGPoint)rightShoulder
                       confidence:(CGFloat)confidence {
    // Update status with confidence
    self.statusLabel.text = [NSString stringWithFormat:@"姿态置信度: %.0f%%", confidence * 100];
}

- (void)personNotDetected {
    if (self.isRunning) {
        self.statusLabel.text = @"未检测到人物";
        self.poseIndicatorView.backgroundColor = [UIColor redColor];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.previewLayer.frame = self.view.bounds;
    self.poseLayer.frame = self.view.bounds;
}

@end
