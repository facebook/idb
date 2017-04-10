/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestManagerProcessInteractionOperator.h"

#import <FBControlCore/FBControlCore.h>

#import "FBDeviceOperator.h"

@implementation FBTestManagerProcessInteractionOperator

#pragma mark - Initializers

+ (instancetype)withIOSTarget:(id<FBiOSTarget>)iosTarget;
{
  return [[FBTestManagerProcessInteractionOperator alloc] initWithIOSTarget:iosTarget];
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

#pragma mark - FBTestManagerMediatorDelegate

- (BOOL)testManagerMediator:(FBTestManagerAPIMediator *)mediator launchApplication:(FBApplicationLaunchConfiguration *)configuration atPath:(NSString *)path error:(NSError **)error
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

- (BOOL)testManagerMediator:(FBTestManagerAPIMediator *)mediator killApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  return [self.iosTarget killApplicationWithBundleID:bundleID error:error];
}

@end
