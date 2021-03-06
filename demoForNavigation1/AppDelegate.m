//
//  AppDelegate.m
//  demoForNavigation1
//
//  Created by 姚振兴 on 16/2/16.
//  Copyright © 2016年 YZX. All rights reserved.
//

#import "AppDelegate.h"
#import "ViewController.h"

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    UITabBarController * tabController = [[UITabBarController alloc] init];
    UINavigationController * nav1 = [[UINavigationController alloc] initWithRootViewController:[[ViewController alloc]init]];//UIViewController可以自定义
    nav1.tabBarItem.title = @"first";
    nav1.tabBarItem.image = nil;
//    nav1.navigationBar.backgroundColor = [UIColor redColor];//背景而已
    nav1.navigationBar.barTintColor = [UIColor redColor];
    nav1.hidesBottomBarWhenPushed = YES;
    //看来标题要在每个vc中设置self.title
//    nav1.title = @"first";
//    nav1.navigationItem.title = @"first";
    UINavigationController * nav2 = [[UINavigationController alloc] initWithRootViewController:[[UIViewController alloc]init]];
    nav2.tabBarItem.title = @"second";
    nav2.tabBarItem.image = nil;
    UINavigationController * nav3 = [[UINavigationController alloc] initWithRootViewController:[[UIViewController alloc]init]];
    nav3.tabBarItem.title = @"three";
    nav3.tabBarItem.image = nil;
    [tabController setViewControllers:@[nav1,nav2,nav3]];
    self.window.rootViewController = tabController;//[[UINavigationController alloc] init];
    //[[ViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@end
