//
//  CourtLineViewController.m
//  demoForNavigation1
//
//  View controller for basketball court line detection
//  Displays detected court lines color-coded by type
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

// Line overlay layers
@property (nonatomic, strong) CAShapeLayer *baselineLayer;      // Red - baseline
@property (nonatomic, strong) CAShapeLayer *halfCourtLayer;     // Blue - half-court line
@property (nonatomic, strong) CAShapeLayer *sidelineLayer;      // Green - sidelines
@property (nonatomic, strong) CAShapeLayer *freeThrowLayer;     // Yellow - free throw line
@property (nonatomic, strong) CAShapeLayer *laneLineLayer;      // Cyan - lane lines
@property (nonatomic, strong) CAShapeLayer *otherLineLayer;     // Gray - unclassified

// UI Elements
@property (nonatomic, strong) UIView *cameraContainerView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UISlider *contrastSlider;
@property (nonatomic, strong) UILabel *contrastLabel;
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
    self.detector.contrastAdjustment = 1.5;
    self.detector.minLineLength = 0.08;
    self.detector.angleThreshold = 20.0;
}

- (void)setupLineLayers {
    // Baseline (red)
    self.baselineLayer = [self createShapeLayerWithColor:[UIColor redColor]];
    // Half-court line (blue)
    self.halfCourtLayer = [self createShapeLayerWithColor:[UIColor blueColor]];
    // Sidelines (green)
    self.sidelineLayer = [self createShapeLayerWithColor:[UIColor greenColor]];
    // Free throw line (yellow)
    self.freeThrowLayer = [self createShapeLayerWithColor:[UIColor yellowColor]];
    // Lane lines (cyan)
    self.laneLineLayer = [self createShapeLayerWithColor:[UIColor cyanColor]];
    // Other lines (gray, dimmer)
    self.otherLineLayer = [self createShapeLayerWithColor:[[UIColor grayColor] colorWithAlphaComponent:0.5]];
    self.otherLineLayer.lineWidth = 1.5;
}

- (CAShapeLayer *)createShapeLayerWithColor:(UIColor *)color {
    CAShapeLayer *layer = [CAShapeLayer layer];
    layer.strokeColor = color.CGColor;
    layer.fillColor = [UIColor clearColor].CGColor;
    layer.lineWidth = 3.0;
    layer.lineCap = kCALineCapRound;
    return layer;
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

    // Detail label
    self.detailLabel = [[UILabel alloc] init];
    self.detailLabel.text = @"横线: 0  竖线: 0";
    self.detailLabel.textColor = [UIColor lightGrayColor];
    self.detailLabel.textAlignment = NSTextAlignmentCenter;
    self.detailLabel.font = [UIFont systemFontOfSize:14];
    self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.detailLabel];

    // Legend view
    [self setupLegendView];

    // Contrast slider label
    self.contrastLabel = [[UILabel alloc] init];
    self.contrastLabel.text = @"对比度: 1.5";
    self.contrastLabel.textColor = [UIColor lightGrayColor];
    self.contrastLabel.font = [UIFont systemFontOfSize:14];
    self.contrastLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.contrastLabel];

    // Contrast slider
    self.contrastSlider = [[UISlider alloc] init];
    self.contrastSlider.minimumValue = 0.5;
    self.contrastSlider.maximumValue = 3.0;
    self.contrastSlider.value = 1.5;
    self.contrastSlider.tintColor = [UIColor cyanColor];
    self.contrastSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contrastSlider addTarget:self action:@selector(contrastChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.contrastSlider];

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
        // Camera container - taller for portrait phone shooting
        [self.cameraContainerView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [self.cameraContainerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [self.cameraContainerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
        [self.cameraContainerView.heightAnchor constraintEqualToAnchor:self.cameraContainerView.widthAnchor multiplier:4.0/3.0],

        // Status label
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.cameraContainerView.bottomAnchor constant:12],
        [self.statusLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        // Detail label
        [self.detailLabel.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:4],
        [self.detailLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        // Legend view
        [self.legendView.topAnchor constraintEqualToAnchor:self.detailLabel.bottomAnchor constant:10],
        [self.legendView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.legendView.heightAnchor constraintEqualToConstant:50],
        [self.legendView.widthAnchor constraintEqualToConstant:320],

        // Contrast label
        [self.contrastLabel.topAnchor constraintEqualToAnchor:self.legendView.bottomAnchor constant:15],
        [self.contrastLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.contrastLabel.widthAnchor constraintEqualToConstant:90],

        // Contrast slider
        [self.contrastSlider.centerYAnchor constraintEqualToAnchor:self.contrastLabel.centerYAnchor],
        [self.contrastSlider.leadingAnchor constraintEqualToAnchor:self.contrastLabel.trailingAnchor constant:10],
        [self.contrastSlider.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

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

    // Row 1
    [self addLegendItem:@"底线" color:[UIColor redColor] atX:0 y:0];
    [self addLegendItem:@"中线" color:[UIColor blueColor] atX:80 y:0];
    [self addLegendItem:@"边线" color:[UIColor greenColor] atX:160 y:0];
    [self addLegendItem:@"罚球线" color:[UIColor yellowColor] atX:240 y:0];

    // Row 2
    [self addLegendItem:@"罚球区" color:[UIColor cyanColor] atX:0 y:25];
    [self addLegendItem:@"其他" color:[UIColor grayColor] atX:80 y:25];
}

- (void)addLegendItem:(NSString *)title color:(UIColor *)color atX:(CGFloat)x y:(CGFloat)y {
    UIView *colorBox = [[UIView alloc] initWithFrame:CGRectMake(x, y + 2, 12, 12)];
    colorBox.backgroundColor = color;
    colorBox.layer.cornerRadius = 2;
    [self.legendView addSubview:colorBox];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(x + 16, y, 60, 16)];
    label.text = title;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:11];
    [self.legendView addSubview:label];
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

    // Add line layers on top
    [self.cameraContainerView.layer addSublayer:self.otherLineLayer];
    [self.cameraContainerView.layer addSublayer:self.laneLineLayer];
    [self.cameraContainerView.layer addSublayer:self.freeThrowLayer];
    [self.cameraContainerView.layer addSublayer:self.sidelineLayer];
    [self.cameraContainerView.layer addSublayer:self.halfCourtLayer];
    [self.cameraContainerView.layer addSublayer:self.baselineLayer];

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
    self.baselineLayer.frame = bounds;
    self.halfCourtLayer.frame = bounds;
    self.sidelineLayer.frame = bounds;
    self.freeThrowLayer.frame = bounds;
    self.laneLineLayer.frame = bounds;
    self.otherLineLayer.frame = bounds;
}

#pragma mark - Actions

- (void)toggleDetection {
    if (self.isRunning) {
        [self.detector stopDetection];
        self.isRunning = NO;
        [self.startButton setTitle:@"开始检测" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:0.9 alpha:1.0];
        self.statusLabel.text = @"已暂停";
        [self clearAllLayers];
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

- (void)clearAllLayers {
    self.baselineLayer.path = nil;
    self.halfCourtLayer.path = nil;
    self.sidelineLayer.path = nil;
    self.freeThrowLayer.path = nil;
    self.laneLineLayer.path = nil;
    self.otherLineLayer.path = nil;
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (pixelBuffer) {
        [self.detector processPixelBuffer:pixelBuffer];
    }
}

#pragma mark - CourtLineDetectorDelegate

- (void)courtLineDetector:(id)detector didDetectCourt:(DetectedCourt *)court inImageSize:(CGSize)imageSize {
    // Update status
    NSInteger totalLines = court.horizontalLines.count + court.verticalLines.count;
    self.detailLabel.text = [NSString stringWithFormat:@"横线: %lu  竖线: %lu",
                             (unsigned long)court.horizontalLines.count,
                             (unsigned long)court.verticalLines.count];

    if (court.isCourtDetected) {
        self.statusLabel.text = @"检测到球场";
        self.statusLabel.textColor = [UIColor greenColor];
    } else if (totalLines > 0) {
        self.statusLabel.text = @"检测中...";
        self.statusLabel.textColor = [UIColor yellowColor];
    } else {
        self.statusLabel.text = @"未检测到场地线";
        self.statusLabel.textColor = [UIColor redColor];
    }

    // Draw lines by type
    [self drawLines:court];
}

- (void)drawLines:(DetectedCourt *)court {
    CGRect bounds = self.cameraContainerView.bounds;
    CGFloat viewWidth = bounds.size.width;
    CGFloat viewHeight = bounds.size.height;

    UIBezierPath *baselinePath = [UIBezierPath bezierPath];
    UIBezierPath *halfCourtPath = [UIBezierPath bezierPath];
    UIBezierPath *sidelinePath = [UIBezierPath bezierPath];
    UIBezierPath *freeThrowPath = [UIBezierPath bezierPath];
    UIBezierPath *laneLinePath = [UIBezierPath bezierPath];
    UIBezierPath *otherPath = [UIBezierPath bezierPath];

    // Draw horizontal lines
    for (DetectedLine *line in court.horizontalLines) {
        UIBezierPath *linePath = [self pathForLine:line viewWidth:viewWidth viewHeight:viewHeight];

        switch (line.lineType) {
            case CourtLineTypeBaseline:
                [baselinePath appendPath:linePath];
                break;
            case CourtLineTypeHalfCourtLine:
                [halfCourtPath appendPath:linePath];
                break;
            case CourtLineTypeFreeThrowLine:
                [freeThrowPath appendPath:linePath];
                break;
            default:
                [otherPath appendPath:linePath];
                break;
        }
    }

    // Draw vertical lines
    for (DetectedLine *line in court.verticalLines) {
        UIBezierPath *linePath = [self pathForLine:line viewWidth:viewWidth viewHeight:viewHeight];

        switch (line.lineType) {
            case CourtLineTypeSideline:
                [sidelinePath appendPath:linePath];
                break;
            case CourtLineTypeLaneLine:
                [laneLinePath appendPath:linePath];
                break;
            default:
                [otherPath appendPath:linePath];
                break;
        }
    }

    // Draw other lines (arcs, etc.)
    for (DetectedLine *line in court.arcLines) {
        UIBezierPath *linePath = [self pathForLine:line viewWidth:viewWidth viewHeight:viewHeight];
        [otherPath appendPath:linePath];
    }

    // Update layers
    self.baselineLayer.path = baselinePath.CGPath;
    self.halfCourtLayer.path = halfCourtPath.CGPath;
    self.sidelineLayer.path = sidelinePath.CGPath;
    self.freeThrowLayer.path = freeThrowPath.CGPath;
    self.laneLineLayer.path = laneLinePath.CGPath;
    self.otherLineLayer.path = otherPath.CGPath;
}

- (UIBezierPath *)pathForLine:(DetectedLine *)line viewWidth:(CGFloat)viewWidth viewHeight:(CGFloat)viewHeight {
    // Transform from normalized Vision coords to view coords
    // Vision: (0,0) bottom-left, (1,1) top-right
    // Camera is landscape, display is portrait - need rotation

    // Rotate 90 degrees: x' = y, y' = 1 - x
    CGFloat startX = line.startPoint.y * viewWidth;
    CGFloat startY = (1.0 - line.startPoint.x) * viewHeight;
    CGFloat endX = line.endPoint.y * viewWidth;
    CGFloat endY = (1.0 - line.endPoint.x) * viewHeight;

    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(startX, startY)];
    [path addLineToPoint:CGPointMake(endX, endY)];

    return path;
}

- (void)courtLineDetectionFailed:(NSString *)reason {
    self.statusLabel.text = reason;
    self.statusLabel.textColor = [UIColor redColor];
    [self clearAllLayers];
}

@end
