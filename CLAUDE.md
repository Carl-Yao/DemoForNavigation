# CLAUDE.md - AI Assistant Guide for demoForNavigation1

This document provides guidance for AI assistants working with this iOS navigation demo project.

## Project Overview

**demoForNavigation1** is an iOS educational/demo application showcasing navigation patterns in iOS development. The project demonstrates:
- Tab bar controller navigation with multiple tabs
- UINavigationController stack-based navigation
- View controller hierarchy and transitions
- Programmatic UI setup (no storyboards for main UI)
- **Ball Bouncing Detection** - Uses Vision framework to detect ball bouncing actions via body pose estimation
- **Court Line Detection** - Uses Core Image and Vision framework to detect basketball court lines
- **Shooting Detection** - Uses Vision framework to detect basketball shooting motions via arm pose analysis

**Created:** February 2016 by 姚振兴 (Yao Zhenxing)

## Technology Stack

| Technology | Details |
|------------|---------|
| Language | Objective-C |
| Platform | iOS (iPhone) |
| Minimum iOS Version | 14.0 |
| Frameworks | UIKit, Foundation, AVFoundation, Vision, CoreImage |
| Build System | Xcode (xcodebuild) |
| Memory Management | ARC (Automatic Reference Counting) |

## Codebase Structure

```
/DemoForNavigation/
├── CLAUDE.md                              # This file
├── demoForNavigation1/                    # Main application source code
│   ├── AppDelegate.h                      # Application delegate interface
│   ├── AppDelegate.m                      # Application delegate implementation
│   ├── ViewController.h                   # Main view controller interface
│   ├── ViewController.m                   # Main view controller implementation
│   ├── BallBouncingDetector.h             # Ball bouncing detection interface
│   ├── BallBouncingDetector.m             # Ball bouncing detection implementation
│   ├── BallBouncingViewController.h       # Ball bouncing view controller interface
│   ├── BallBouncingViewController.m       # Ball bouncing view controller implementation
│   ├── CourtLineDetector.h                # Court line detection interface
│   ├── CourtLineDetector.m                # Court line detection implementation
│   ├── CourtLineViewController.h          # Court line view controller interface
│   ├── CourtLineViewController.m          # Court line view controller implementation
│   ├── ShootingDetector.h                 # Shooting detection interface
│   ├── ShootingDetector.m                 # Shooting detection implementation
│   ├── ShootingViewController.h           # Shooting view controller interface
│   ├── ShootingViewController.m           # Shooting view controller implementation
│   ├── main.m                             # Application entry point
│   ├── Info.plist                         # App configuration and metadata
│   ├── Assets.xcassets/                   # Image and asset catalog
│   │   └── AppIcon.appiconset/           # App icon assets
│   └── Base.lproj/
│       └── LaunchScreen.storyboard       # Launch screen UI
└── demoForNavigation1.xcodeproj/          # Xcode project bundle
    ├── project.pbxproj                    # Project configuration
    └── project.xcworkspace/               # Workspace definition
```

### Key Files

| File | Purpose |
|------|---------|
| `AppDelegate.m` | Sets up the tab bar controller with 4 tabs and navigation controllers |
| `ViewController.m` | Demonstrates navigation push/pop and navigation bar customization |
| `BallBouncingDetector.m` | Core detection logic using Vision framework for body pose estimation |
| `BallBouncingViewController.m` | Camera UI and detection interface for ball bouncing feature |
| `CourtLineDetector.m` | Core detection logic using Core Image edge detection and Vision contours |
| `CourtLineViewController.m` | Camera UI and detection interface for court line feature |
| `ShootingDetector.m` | Core detection logic using Vision framework for shooting motion analysis |
| `ShootingViewController.m` | Camera UI and detection interface for shooting detection feature |
| `main.m` | Standard iOS entry point calling UIApplicationMain |
| `Info.plist` | Bundle identifier, version, supported orientations, camera permission |
| `project.pbxproj` | Xcode project settings, build phases, and configurations |

## Architecture

The app uses a **Tab Bar + Navigation Controller** architecture:

```
UIWindow
└── UITabBarController (4 tabs)
    ├── Tab 1: UINavigationController → ViewController (navigation demos)
    ├── Tab 2: UINavigationController → BallBouncingViewController (ball bouncing detection)
    ├── Tab 3: UINavigationController → CourtLineViewController (court line detection)
    └── Tab 4: UINavigationController → ShootingViewController (shooting detection)
```

### Design Patterns Used

- **Delegate Pattern:** AppDelegate implements UIApplicationDelegate, BallBouncingDetectorDelegate, CourtLineDetectorDelegate, ShootingDetectorDelegate
- **MVC Architecture:** UIViewController subclasses with view management
- **Target-Action:** Button actions connected via selectors
- **AVFoundation:** Camera capture and video processing pipeline
- **Core Image:** GPU-accelerated image processing for edge detection

### Ball Bouncing Detection

The ball bouncing feature uses Apple's Vision framework to detect human body poses and track wrist movement:

1. **Camera Capture:** AVCaptureSession captures video frames from the back camera
2. **Pose Detection:** VNDetectHumanBodyPoseRequest analyzes frames to detect body joints
3. **Wrist Tracking:** The detector tracks wrist Y position over time
4. **Bounce Detection:** Identifies up-down movement patterns that match ball bouncing motion
5. **UI Feedback:** Real-time count display with visual indicators for movement direction

### Court Line Detection

The court line detection feature uses Core Image filters and Vision framework to detect basketball court lines:

1. **Camera Capture:** AVCaptureSession captures video frames at 720p resolution
2. **Image Processing:** Core Image filters enhance contrast and convert to grayscale
3. **Edge Detection:** CIEdges filter detects edges in the image using Sobel-like convolution
4. **Contour Analysis:** VNDetectContoursRequest counts detected line contours
5. **UI Feedback:** Real-time display with adjustable edge intensity and overlay options

**Detection Pipeline:**
- `CIColorControls` → Grayscale conversion and contrast enhancement
- `CIEdges` → Edge detection with adjustable intensity
- `CIExposureAdjust` → Edge enhancement
- `CIScreenBlendMode` → Optional overlay with original image

### Shooting Detection

The shooting detection feature uses Apple's Vision framework to detect basketball shooting motions:

1. **Camera Capture:** AVCaptureSession captures video frames from the back camera
2. **Pose Detection:** VNDetectHumanBodyPoseRequest analyzes frames to detect body joints
3. **Arm Tracking:** Tracks wrist, elbow, and shoulder positions of the shooting arm
4. **Phase Detection:** Uses a state machine to identify shooting phases:
   - **Idle:** Waiting for shooting motion
   - **Ready:** Arm in preparation position
   - **Raising:** Ball being raised above head
   - **Release:** Shot released (arm extension detected)
   - **Follow Through:** Post-shot position
5. **UI Feedback:** Real-time shot count with phase indicators and animations

**Detection Algorithm:**
- Monitors wrist position relative to shoulder height
- Tracks peak wrist height during raising phase
- Detects release when wrist starts descending after peak
- Includes debounce (1 second minimum between shots)

## Development Workflows

### Building the Project

**Using Xcode:**
1. Open `demoForNavigation1.xcodeproj` in Xcode
2. Select target device/simulator
3. Press Cmd+B to build or Cmd+R to run

**Using Command Line:**
```bash
# Build for simulator
xcodebuild -project demoForNavigation1.xcodeproj \
           -scheme demoForNavigation1 \
           -sdk iphonesimulator \
           build

# Build for device (requires code signing)
xcodebuild -project demoForNavigation1.xcodeproj \
           -scheme demoForNavigation1 \
           -sdk iphoneos \
           build
```

### Build Configurations

| Configuration | Purpose |
|---------------|---------|
| Debug | Development with debug info, active arch only |
| Release | Production build with validation |

### Project Settings

- **Bundle Identifier:** `YZX.demoForNavigation1`
- **Deployment Target:** iOS 14.0
- **Device Family:** iPhone
- **Supported Orientations:** Portrait, Landscape Left, Landscape Right
- **Privacy:** Camera usage permission required for ball bouncing and court line detection

## Code Conventions

### Naming Conventions

- **Classes:** PascalCase (e.g., `AppDelegate`, `ViewController`)
- **Methods:** camelCase with descriptive names (e.g., `didTapNextButton:`)
- **Properties:** camelCase (e.g., `tabBarController`, `navigationController`)
- **Constants:** Not explicitly defined in this codebase

### Objective-C Patterns

```objc
// Object creation (alloc-init pattern)
UITabBarController *tabBarController = [[UITabBarController alloc] init];

// Property access
self.window.rootViewController = tabBarController;

// Delegate method signatures
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;

// Action methods
- (void)didTapNextButton:(id)sender;
```

### File Organization

- **Header files (.h):** Interface declarations, public API
- **Implementation files (.m):** Method implementations
- **Class extensions:** Private properties/methods in implementation files

### Comments

- Comments are in mixed Chinese and English
- Copyright headers at the top of each file
- Inline comments explain navigation behavior

## UI/Navigation Conventions

### Navigation Bar Customization

```objc
// Custom tint color
navigationController.navigationBar.barTintColor = [UIColor redColor];

// Setting title
self.title = @"Title Text";
```

### Push Navigation

```objc
// Push with animation
[self.navigationController pushViewController:vc animated:YES];

// Hide bottom bar when pushed
vc.hidesBottomBarWhenPushed = YES;
```

### Tab Bar Setup

```objc
UITabBarItem *tabItem = [[UITabBarItem alloc] initWithTitle:@"first"
                                                     image:nil
                                                       tag:1];
viewController.tabBarItem = tabItem;
```

## Guidelines for AI Assistants

### When Modifying Code

1. **Preserve the Objective-C style** - Don't convert to Swift unless explicitly requested
2. **Maintain ARC compatibility** - Don't add manual retain/release calls
3. **Follow existing naming conventions** - Use camelCase for methods, PascalCase for classes
4. **Keep UI setup programmatic** - The main UI is built in code, not storyboards
5. **Test on iOS 14.0+** - Ensure compatibility with deployment target (Vision body pose requires iOS 14+)

### When Adding Features

1. **New view controllers** should follow the existing ViewController pattern
2. **Navigation changes** should go through the navigation controller stack
3. **New tabs** should be added to the tab bar controller in AppDelegate
4. **Assets** should be added to Assets.xcassets with proper scaling

### Common Tasks

| Task | Location |
|------|----------|
| Add a new screen | Create new ViewController subclass, push via navigation |
| Change app styling | Modify navigation bar in AppDelegate or individual VCs |
| Add tab bar items | Update tabBarController setup in AppDelegate.m |
| Modify launch behavior | Edit AppDelegate.m's didFinishLaunchingWithOptions |

### Things to Avoid

- Don't add storyboard files for main UI (project uses programmatic UI)
- Don't upgrade minimum iOS version without explicit request
- Don't add external dependencies/CocoaPods without approval
- Don't modify xcuserdata files (user-specific settings)

## Version Control

- **Main Branch:** master
- **Feature branches** should be prefixed with `claude/` for AI-assisted work
- Commit messages should be descriptive of the changes made

## Additional Notes

- This project demonstrates navigation patterns and multiple computer vision capabilities
- Uses only Apple native frameworks (no external dependencies)
- No unit tests currently in place
- Project was created with Xcode 7.2, updated for Vision and Core Image support
- Ball bouncing, court line, and shooting detection require a real device with camera (simulator has limited support)
- Court line detection works best in well-lit environments with clear court markings
- Shooting detection works best when the full upper body is visible in frame

---

*Last updated: 2026-02-03*
