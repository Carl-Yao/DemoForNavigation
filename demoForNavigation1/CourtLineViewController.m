//
//  CourtLineViewController.m
//  demoForNavigation1
//
//  View controller for basketball court line detection
//  Displays edge-detected image overlay on camera preview
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

// Edge image overlay
@property (nonatomic, strong) UIImageView *edgeImageView;

// UI Elements
@property (nonatomic, strong) UIView *cameraContainerView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UISlider *intensitySlider;
@property (nonatomic, strong) UILabel *intensityLabel;
@property (nonatomic, strong) UISwitch *colorSwitch;
@property (nonatomic, strong) UILabel *colorLabel;

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
    self.detector.edgeIntensity = 1.0;
    self.detector.threshold = 0.6;  // Brightness threshold for white lines
    self.detector.showColorEdges = YES;  // Show lines on original image by default
}

- (void)setupUI {
    // Camera container view
    self.cameraContainerView = [[UIView alloc] init];
    self.cameraContainerView.backgroundColor = [UIColor darkGrayColor];
    self.cameraContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cameraContainerView.clipsToBounds = YES;
    self.cameraContainerView.layer.cornerRadius = 8;
    [self.view addSubview:self.cameraContainerView];

    // Edge image overlay view
    self.edgeImageView = [[UIImageView alloc] init];
    self.edgeImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.edgeImageView.clipsToBounds = YES;
    self.edgeImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.edgeImageView.alpha = 0.8;  // Semi-transparent overlay

    // Status label
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"准备就绪";
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:18];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];

    // Intensity slider label (now for threshold)
    self.intensityLabel = [[UILabel alloc] init];
    self.intensityLabel.text = @"白线阈值: 0.6";
    self.intensityLabel.textColor = [UIColor lightGrayColor];
    self.intensityLabel.font = [UIFont systemFontOfSize:14];
    self.intensityLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.intensityLabel];

    // Intensity slider (controls brightness threshold for white line detection)
    self.intensitySlider = [[UISlider alloc] init];
    self.intensitySlider.minimumValue = 0.3;
    self.intensitySlider.maximumValue = 0.9;
    self.intensitySlider.value = 0.6;
    self.intensitySlider.tintColor = [UIColor cyanColor];
    self.intensitySlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.intensitySlider addTarget:self action:@selector(intensityChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.intensitySlider];

    // Color switch label
    self.colorLabel = [[UILabel alloc] init];
    self.colorLabel.text = @"叠加原图:";
    self.colorLabel.textColor = [UIColor lightGrayColor];
    self.colorLabel.font = [UIFont systemFontOfSize:14];
    self.colorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.colorLabel];

    // Color switch
    self.colorSwitch = [[UISwitch alloc] init];
    self.colorSwitch.on = YES;  // Show lines on original image by default
    self.colorSwitch.onTintColor = [UIColor cyanColor];
    self.colorSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.colorSwitch addTarget:self action:@selector(colorSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.colorSwitch];

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
        [self.cameraContainerView.heightAnchor constraintEqualToAnchor:self.cameraContainerView.widthAnchor multiplier:4.0/3.0],

        // Status label
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.cameraContainerView.bottomAnchor constant:20],
        [self.statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        // Intensity label
        [self.intensityLabel.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:25],
        [self.intensityLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.intensityLabel.widthAnchor constraintEqualToConstant:110],

        // Intensity slider
        [self.intensitySlider.centerYAnchor constraintEqualToAnchor:self.intensityLabel.centerYAnchor],
        [self.intensitySlider.leadingAnchor constraintEqualToAnchor:self.intensityLabel.trailingAnchor constant:10],
        [self.intensitySlider.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        // Color label
        [self.colorLabel.topAnchor constraintEqualToAnchor:self.intensityLabel.bottomAnchor constant:20],
        [self.colorLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],

        // Color switch
        [self.colorSwitch.centerYAnchor constraintEqualToAnchor:self.colorLabel.centerYAnchor],
        [self.colorSwitch.leadingAnchor constraintEqualToAnchor:self.colorLabel.trailingAnchor constant:10],

        // Start button
        [self.startButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-30],
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

    // Add edge image view on top of preview
    [self.cameraContainerView addSubview:self.edgeImageView];
    [NSLayoutConstraint activateConstraints:@[
        [self.edgeImageView.topAnchor constraintEqualToAnchor:self.cameraContainerView.topAnchor],
        [self.edgeImageView.bottomAnchor constraintEqualToAnchor:self.cameraContainerView.bottomAnchor],
        [self.edgeImageView.leadingAnchor constraintEqualToAnchor:self.cameraContainerView.leadingAnchor],
        [self.edgeImageView.trailingAnchor constraintEqualToAnchor:self.cameraContainerView.trailingAnchor],
    ]];

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
}

#pragma mark - Actions

- (void)toggleDetection {
    if (self.isRunning) {
        [self.detector stopDetection];
        self.isRunning = NO;
        [self.startButton setTitle:@"开始检测" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:0.9 alpha:1.0];
        self.statusLabel.text = @"已暂停";
        self.edgeImageView.image = nil;
        self.edgeImageView.hidden = YES;
    } else {
        [self.detector startDetection];
        self.isRunning = YES;
        [self.startButton setTitle:@"停止检测" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:1.0];
        self.statusLabel.text = @"检测中...";
        self.edgeImageView.hidden = NO;
    }
}

- (void)intensityChanged:(UISlider *)slider {
    self.detector.threshold = slider.value;
    self.intensityLabel.text = [NSString stringWithFormat:@"白线阈值: %.1f", slider.value];
}

- (void)colorSwitchChanged:(UISwitch *)colorSwitch {
    self.detector.showColorEdges = colorSwitch.on;
    if (colorSwitch.on) {
        self.edgeImageView.alpha = 1.0;
    } else {
        self.edgeImageView.alpha = 0.8;
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

- (void)courtLineDetectorDidDetectEdges:(UIImage *)edgeImage {
    self.edgeImageView.image = edgeImage;
    self.statusLabel.text = @"检测到边缘";
    self.statusLabel.textColor = [UIColor greenColor];
}

- (void)courtLineDetectionFailed:(NSString *)reason {
    self.statusLabel.text = reason;
    self.statusLabel.textColor = [UIColor redColor];
    self.edgeImageView.image = nil;
}

@end
