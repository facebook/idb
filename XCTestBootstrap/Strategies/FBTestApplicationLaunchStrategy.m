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

#pragma mark Private

- (FBFuture<FBInstalledApplication *> *)installedAppWithBundleID:(NSString *)bundleID
{
  return [[self.iosTarget
    installedApplications]
    onQueue:self.iosTarget.workQueue fmap:^(NSArray<FBInstalledApplication *> *apps) {
      for (FBInstalledApplication *app in apps) {
        if ([app.bundle.bundleID isEqualToString:bundleID]) {
          return [FBFuture futureWithResult:app];
        }
      }
      return [[FBControlCoreError
        describeFormat:@"App with bundle ID %@ is not installed", bundleID]
        failFuture];
    }];
}

- (FBFuture<NSNumber *> *)installAndLaunchApplication:(FBApplicationLaunchConfiguration *)configuration atPath:(NSString *)path
{
  if (!path) {
    return [[FBControlCoreError
      describeFormat:@"Could not install App-Under-Test %@ as it is not installed and no path was provided", configuration]
      failFuture];
  }
  FBFuture<NSNull *> *cleanState = [[self.iosTarget
    isApplicationInstalledWithBundleID:configuration.bundleID]
    onQueue:self.iosTarget.workQueue fmap:^FBFuture<NSNull *> *(NSNumber *isInstalled) {
      if (!isInstalled.boolValue) {
        return [FBFuture futureWithResult:NSNull.null];
      }
      return [self.iosTarget uninstallApplicationWithBundleID:configuration.bundleID];
    }];
  return [[cleanState
    onQueue:self.iosTarget.workQueue fmap:^(NSNull *_) {
      return [self.iosTarget installApplicationWithPath:path];
    }]
    onQueue:self.iosTarget.workQueue fmap:^(NSNull *_) {
      return [self.iosTarget launchApplication:configuration];
    }];
}

#pragma mark Public Methods

- (FBFuture<NSNumber *> *)launchApplication:(FBApplicationLaunchConfiguration *)configuration atPath:(NSString *)path
{
  // Check if path points to installed app
  return [[self
    installedAppWithBundleID:configuration.bundleID]
    onQueue:self.iosTarget.workQueue chain:^(FBFuture<FBInstalledApplication *> *future) {
      FBInstalledApplication *app = future.result;
      if (app && [app.bundle.path isEqualToString:path]) {
        return [self.iosTarget launchApplication:configuration];
      }
      return [self installAndLaunchApplication:configuration atPath:path];
    }];
}

@end
