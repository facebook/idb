/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestApplicationLaunchStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import "FBDeviceOperator.h"

@interface FBTestApplicationLaunchStrategy ()

@property (nonatomic, strong, readonly) id<FBiOSTarget> iosTarget;

@end

@implementation FBTestApplicationLaunchStrategy

#pragma mark - Initializers

+ (instancetype)strategyWithTarget:(id<FBiOSTarget>)iosTarget
{
  return [[FBTestApplicationLaunchStrategy alloc] initWithIOSTarget:iosTarget];
}

- (instancetype)initWithIOSTarget:(id<FBiOSTarget>)iosTarget
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _iosTarget = iosTarget;

  return self;
}

- (FBInstalledApplication *)installedAppWithBundleID:(NSString *)bundleID
{
  NSArray<FBInstalledApplication *> *apps = [self.iosTarget installedApplicationsWithError:nil];
  if (!apps) {
    return nil;
  }

  for (FBInstalledApplication *app in apps) {
    if ([app.bundle.bundleID isEqualToString:bundleID]) {
      return app;
    }
  }

  return nil;
}

#pragma mark Public Methods

- (BOOL)launchApplication:(FBApplicationLaunchConfiguration *)configuration atPath:(NSString *)path error:(NSError **)error
{
  // Check if path points to installed app
  FBInstalledApplication *app = [self installedAppWithBundleID:configuration.bundleID];
  if (app && [app.bundle.path isEqualToString:path]) {
    return [self.iosTarget launchApplication:configuration error:error];
  }

  if (!path && ![self.iosTarget isApplicationInstalledWithBundleID:configuration.bundleID error:error]) {
    return NO;
  }
  if (path) {
    if ([self.iosTarget isApplicationInstalledWithBundleID:configuration.bundleID error:error]) {
      if (![[self.iosTarget uninstallApplicationWithBundleID:configuration.bundleID] await:error]) {
        return NO;
      }
    }
    if (![[self.iosTarget installApplicationWithPath:path] awaitWithTimeout:FBControlCoreGlobalConfiguration.slowTimeout error:error]) {
      return NO;
    }
  }
  if (![self.iosTarget launchApplication:configuration error:error]) {
    return NO;
  }
  return YES;
}

@end
