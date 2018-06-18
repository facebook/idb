/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBAppDelegate.h"

@interface FBAppDelegate ()
@end

@implementation FBAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  if (application.applicationState == UIApplicationStateBackground) {
    UIBackgroundTaskIdentifier taskID = [application beginBackgroundTaskWithExpirationHandler:^ {
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
  NSLog(@"Continuing to run tests in the background with task ID %lu", [application beginBackgroundTaskWithExpirationHandler:^ {
    NSLog(@"Background task expired!!!");
  }]);
}

@end
