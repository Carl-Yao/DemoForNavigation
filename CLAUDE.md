# CLAUDE.md - AI Assistant Guide for demoForNavigation1

This document provides guidance for AI assistants working with this iOS navigation demo project.

## Project Overview

**demoForNavigation1** is an iOS educational/demo application showcasing navigation patterns in iOS development. The project demonstrates:
- Tab bar controller navigation with multiple tabs
- UINavigationController stack-based navigation
- View controller hierarchy and transitions
- Programmatic UI setup (no storyboards for main UI)

**Created:** February 2016 by 姚振兴 (Yao Zhenxing)

## Technology Stack

| Technology | Details |
|------------|---------|
| Language | Objective-C |
| Platform | iOS (iPhone) |
| Minimum iOS Version | 9.0 |
| Frameworks | UIKit, Foundation |
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
| `AppDelegate.m` | Sets up the tab bar controller with 3 tabs and navigation controllers |
| `ViewController.m` | Demonstrates navigation push/pop and navigation bar customization |
| `main.m` | Standard iOS entry point calling UIApplicationMain |
| `Info.plist` | Bundle identifier, version, supported orientations, launch storyboard |
| `project.pbxproj` | Xcode project settings, build phases, and configurations |

## Architecture

The app uses a **Tab Bar + Navigation Controller** architecture:

```
UIWindow
└── UITabBarController (3 tabs)
    ├── Tab 1: UINavigationController → ViewController (navigation demos)
    ├── Tab 2: UIViewController (plain)
    └── Tab 3: UIViewController (plain)
```

### Design Patterns Used

- **Delegate Pattern:** AppDelegate implements UIApplicationDelegate
- **MVC Architecture:** UIViewController subclasses with view management
- **Target-Action:** Button actions connected via selectors

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
- **Deployment Target:** iOS 9.0
- **Device Family:** iPhone
- **Supported Orientations:** Portrait, Landscape Left, Landscape Right

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
5. **Test on iOS 9.0+** - Ensure compatibility with deployment target

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

- This is a lightweight demo project (~158 lines of source code)
- No external dependencies or third-party frameworks
- No unit tests currently in place
- Project was created with Xcode 7.2

---

*Last updated: 2026-02-03*
