//
//  CourtLineViewController.m
//  demoForNavigation1
//
//  View controller for basketball court line detection with camera
//

#import "CourtLineViewController.h"
#import "CourtLineDetector.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>

@interface CourtLineViewController () <AVCaptureVideoDataOutputSampleBufferDelegate, CourtLineDetectorDelegate>

// Camera
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) dispatch_queue_t videoQueue;

// Detector
@property (nonatomic, strong) CourtLineDetector *detector;

// UI Elements
@property (nonatomic, strong) UIImageView *previewImageView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *lineCountLabel;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UISlider *intensitySlider;
@property (nonatomic, strong) UILabel *intensityLabel;
@property (nonatomic, strong) UISwitch *overlaySwitch;
@property (nonatomic, strong) UILabel *overlayLabel;

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
    self.detector.edgeIntensity = 0.7;
    self.detector.showOriginalOverlay = YES;
}

- (void)setupUI {
    // Preview image view for showing processed frames
    self.previewImageView = [[UIImageView alloc] init];
    self.previewImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.previewImageView.backgroundColor = [UIColor darkGrayColor];
    self.previewImageView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.previewImageView];

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
    self.lineCountLabel.text = @"检测到线条: 0";
    self.lineCountLabel.textColor = [UIColor greenColor];
    self.lineCountLabel.textAlignment = NSTextAlignmentCenter;
    self.lineCountLabel.font = [UIFont boldSystemFontOfSize:20];
    self.lineCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.lineCountLabel];

    // Intensity slider label
    self.intensityLabel = [[UILabel alloc] init];
    self.intensityLabel.text = @"边缘强度: 70%";
    self.intensityLabel.textColor = [UIColor lightGrayColor];
    self.intensityLabel.font = [UIFont systemFontOfSize:14];
    self.intensityLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.intensityLabel];

    // Intensity slider
    self.intensitySlider = [[UISlider alloc] init];
    self.intensitySlider.minimumValue = 0.1;
    self.intensitySlider.maximumValue = 1.0;
    self.intensitySlider.value = 0.7;
    self.intensitySlider.tintColor = [UIColor greenColor];
    self.intensitySlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.intensitySlider addTarget:self action:@selector(intensityChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.intensitySlider];

    // Overlay switch label
    self.overlayLabel = [[UILabel alloc] init];
    self.overlayLabel.text = @"显示原图叠加";
    self.overlayLabel.textColor = [UIColor lightGrayColor];
    self.overlayLabel.font = [UIFont systemFontOfSize:14];
    self.overlayLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.overlayLabel];

    // Overlay switch
    self.overlaySwitch = [[UISwitch alloc] init];
    self.overlaySwitch.on = YES;
    self.overlaySwitch.onTintColor = [UIColor greenColor];
    self.overlaySwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.overlaySwitch addTarget:self action:@selector(overlayToggled:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.overlaySwitch];

    // Start/Stop button
    self.startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.startButton setTitle:@"开始检测" forState:UIControlStateNormal];
    [self.startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:0.8 alpha:1.0];
    self.startButton.layer.cornerRadius = 25;
    self.startButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.startButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.startButton addTarget:self action:@selector(toggleDetection) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.startButton];

    // Layout constraints
    [NSLayoutConstraint activateConstraints:@[
        // Preview image view
        [self.previewImageView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [self.previewImageView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.previewImageView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.previewImageView.heightAnchor constraintEqualToAnchor:self.previewImageView.widthAnchor multiplier:0.75],

        // Status label
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.previewImageView.bottomAnchor constant:15],
        [self.statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        // Line count label
        [self.lineCountLabel.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:10],
        [self.lineCountLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        // Intensity label
        [self.intensityLabel.topAnchor constraintEqualToAnchor:self.lineCountLabel.bottomAnchor constant:20],
        [self.intensityLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],

        // Intensity slider
        [self.intensitySlider.centerYAnchor constraintEqualToAnchor:self.intensityLabel.centerYAnchor],
        [self.intensitySlider.leadingAnchor constraintEqualToAnchor:self.intensityLabel.trailingAnchor constant:10],
        [self.intensitySlider.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        // Overlay label
        [self.overlayLabel.topAnchor constraintEqualToAnchor:self.intensityLabel.bottomAnchor constant:15],
        [self.overlayLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],

        // Overlay switch
        [self.overlaySwitch.centerYAnchor constraintEqualToAnchor:self.overlayLabel.centerYAnchor],
        [self.overlaySwitch.leadingAnchor constraintEqualToAnchor:self.overlayLabel.trailingAnchor constant:10],

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

#pragma mark - Actions

- (void)toggleDetection {
    if (self.isRunning) {
        [self.detector stopDetection];
        self.isRunning = NO;
        [self.startButton setTitle:@"开始检测" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:0.8 alpha:1.0];
        self.statusLabel.text = @"已暂停";
    } else {
        [self.detector startDetection];
        self.isRunning = YES;
        [self.startButton setTitle:@"停止检测" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1.0];
        self.statusLabel.text = @"检测中...";
    }
}

- (void)intensityChanged:(UISlider *)slider {
    self.detector.edgeIntensity = slider.value;
    self.intensityLabel.text = [NSString stringWithFormat:@"边缘强度: %.0f%%", slider.value * 100];
}

- (void)overlayToggled:(UISwitch *)overlaySwitch {
    self.detector.showOriginalOverlay = overlaySwitch.on;
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {

    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (pixelBuffer) {
        [self.detector processPixelBuffer:pixelBuffer];
    }
}

#pragma mark - CourtLineDetectorDelegate

- (void)courtLinesDetectedWithImage:(CIImage *)processedImage lineCount:(NSInteger)lineCount {
    // Render CIImage to UIImage for display
    CGImageRef cgImage = [self.detector.ciContext createCGImage:processedImage fromRect:processedImage.extent];
    if (cgImage) {
        UIImage *displayImage = [UIImage imageWithCGImage:cgImage scale:1.0 orientation:UIImageOrientationRight];
        CGImageRelease(cgImage);

        self.previewImageView.image = displayImage;
    }

    self.lineCountLabel.text = [NSString stringWithFormat:@"检测到线条: %ld", (long)lineCount];

    // Update color based on line count
    if (lineCount > 10) {
        self.lineCountLabel.textColor = [UIColor greenColor];
        self.statusLabel.text = @"检测到场地线";
    } else if (lineCount > 0) {
        self.lineCountLabel.textColor = [UIColor yellowColor];
        self.statusLabel.text = @"检测中...";
    } else {
        self.lineCountLabel.textColor = [UIColor redColor];
        self.statusLabel.text = @"未检测到明显线条";
    }
}

- (void)courtLineDetectionFailed:(NSString *)reason {
    self.statusLabel.text = reason;
    self.lineCountLabel.textColor = [UIColor redColor];
}

@end
