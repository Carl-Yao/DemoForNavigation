//
//  BallBouncingViewController.m
//  demoForNavigation1
//
//  View controller for ball bouncing detection with camera
//

#import "BallBouncingViewController.h"
#import "BallBouncingDetector.h"
#import <AVFoundation/AVFoundation.h>

@interface BallBouncingViewController () <AVCaptureVideoDataOutputSampleBufferDelegate, BallBouncingDetectorDelegate>

// Camera
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) dispatch_queue_t videoQueue;

// Detector
@property (nonatomic, strong) BallBouncingDetector *detector;

// UI Elements
@property (nonatomic, strong) UILabel *bounceCountLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIButton *resetButton;
@property (nonatomic, strong) UIView *indicatorView;
@property (nonatomic, strong) UILabel *instructionLabel;

@property (nonatomic, assign) BOOL isRunning;

@end

@implementation BallBouncingViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"拍球检测";
    self.view.backgroundColor = [UIColor blackColor];
    self.isRunning = NO;

    [self setupDetector];
    [self setupUI];
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
    self.detector = [[BallBouncingDetector alloc] init];
    self.detector.delegate = self;
    self.detector.movementThreshold = 0.05;  // 5% movement threshold
}

- (void)setupUI {
    // Instruction label at top
    self.instructionLabel = [[UILabel alloc] init];
    self.instructionLabel.text = @"将手机对准拍球的人\n确保手腕在画面中可见";
    self.instructionLabel.textColor = [UIColor whiteColor];
    self.instructionLabel.textAlignment = NSTextAlignmentCenter;
    self.instructionLabel.numberOfLines = 2;
    self.instructionLabel.font = [UIFont systemFontOfSize:16];
    self.instructionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.instructionLabel];

    // Bounce count label
    self.bounceCountLabel = [[UILabel alloc] init];
    self.bounceCountLabel.text = @"0";
    self.bounceCountLabel.textColor = [UIColor whiteColor];
    self.bounceCountLabel.textAlignment = NSTextAlignmentCenter;
    self.bounceCountLabel.font = [UIFont boldSystemFontOfSize:120];
    self.bounceCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.bounceCountLabel];

    // Status label
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"准备就绪";
    self.statusLabel.textColor = [UIColor lightGrayColor];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:18];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];

    // Movement indicator
    self.indicatorView = [[UIView alloc] init];
    self.indicatorView.backgroundColor = [UIColor grayColor];
    self.indicatorView.layer.cornerRadius = 10;
    self.indicatorView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.indicatorView];

    // Start/Stop button
    self.startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.startButton setTitle:@"开始检测" forState:UIControlStateNormal];
    [self.startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:0.0 alpha:1.0];
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

        // Bounce count
        [self.bounceCountLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.bounceCountLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-50],

        // Status label
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.bounceCountLabel.bottomAnchor constant:10],
        [self.statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        // Indicator
        [self.indicatorView.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:20],
        [self.indicatorView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.indicatorView.widthAnchor constraintEqualToConstant:20],
        [self.indicatorView.heightAnchor constraintEqualToConstant:20],

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
                                                                   message:@"请在设置中允许访问相机以使用拍球检测功能"
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

    self.videoQueue = dispatch_queue_create("com.demo.videoQueue", DISPATCH_QUEUE_SERIAL);
    [videoOutput setSampleBufferDelegate:self queue:self.videoQueue];

    if ([self.captureSession canAddOutput:videoOutput]) {
        [self.captureSession addOutput:videoOutput];
    }

    // Preview layer
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.previewLayer.frame = self.view.bounds;
    self.previewLayer.opacity = 0.3;  // Semi-transparent background
    [self.view.layer insertSublayer:self.previewLayer atIndex:0];

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
        self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:0.0 alpha:1.0];
        self.statusLabel.text = @"已暂停";
    } else {
        [self.detector startDetection];
        self.isRunning = YES;
        [self.startButton setTitle:@"暂停" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.4 blue:0.0 alpha:1.0];
        self.statusLabel.text = @"检测中...";
    }
}

- (void)resetCount {
    [self.detector resetBounceCount];
    self.bounceCountLabel.text = @"0";
    self.statusLabel.text = self.isRunning ? @"检测中..." : @"准备就绪";
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {

    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (pixelBuffer) {
        [self.detector processPixelBuffer:pixelBuffer];
    }
}

#pragma mark - BallBouncingDetectorDelegate

- (void)ballBouncingDetected:(NSInteger)bounceCount {
    self.bounceCountLabel.text = [NSString stringWithFormat:@"%ld", (long)bounceCount];

    // Flash indicator green on bounce
    self.indicatorView.backgroundColor = [UIColor greenColor];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.indicatorView.backgroundColor = [UIColor grayColor];
    });

    // Animate count label
    [UIView animateWithDuration:0.1 animations:^{
        self.bounceCountLabel.transform = CGAffineTransformMakeScale(1.2, 1.2);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.1 animations:^{
            self.bounceCountLabel.transform = CGAffineTransformIdentity;
        }];
    }];
}

- (void)poseUpdatedWithWristY:(CGFloat)wristY isMovingDown:(BOOL)isMovingDown {
    // Update indicator color based on movement direction
    if (isMovingDown) {
        self.indicatorView.backgroundColor = [UIColor orangeColor];
    } else {
        self.indicatorView.backgroundColor = [UIColor blueColor];
    }
}

- (void)personNotDetected {
    if (self.isRunning) {
        self.statusLabel.text = @"未检测到人物";
        self.indicatorView.backgroundColor = [UIColor redColor];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.previewLayer.frame = self.view.bounds;
}

@end
