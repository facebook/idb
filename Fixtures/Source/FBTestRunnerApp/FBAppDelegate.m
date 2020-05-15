/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAppDelegate.h"

@interface FBAppDelegate ()
@end

@implementation FBAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  if (application.applicationState == UIApplicationStateBackground) {
    UIBackgroundTaskIdentifier taskID = [application beginBackgroundTaskWithName:@__FILE__ expirationHandler:^ {
      NSLog(@"Background task expired!!!");
    }];
    if (taskID == UIBackgroundTaskInvalid) {
      NSLog(@"Got invalid background task identifier, execution may be interrupted.");
    }
    else {
      NSLog(@"Running in the background.");
    }
  }
  return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
  NSLog(@"Continuing to run tests in the background with task ID %lu", [application beginBackgroundTaskWithName:@__FILE__ expirationHandler:^ {
    NSLog(@"Background task expired!!!");
  }]);
}

@end
