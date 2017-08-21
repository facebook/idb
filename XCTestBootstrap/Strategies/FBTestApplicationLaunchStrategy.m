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

#pragma mark Public Methods

- (BOOL)launchApplication:(FBApplicationLaunchConfiguration *)configuration atPath:(NSString *)path error:(NSError **)error
{
  if (!path && ![self.iosTarget isApplicationInstalledWithBundleID:configuration.bundleID error:error]) {
    return NO;
  }
  if (path) {
    if ([self.iosTarget isApplicationInstalledWithBundleID:configuration.bundleID error:error]) {
      if (![self.iosTarget uninstallApplicationWithBundleID:configuration.bundleID error:error]) {
        return NO;
      }
    }
    if (![self.iosTarget installApplicationWithPath:path error:error]) {
      return NO;
    }
  }
  if (![self.iosTarget launchApplication:configuration error:error]) {
    return NO;
  }
  return YES;
}

@end
