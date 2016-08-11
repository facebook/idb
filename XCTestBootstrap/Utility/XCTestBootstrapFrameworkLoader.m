/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "XCTestBootstrapFrameworkLoader.h"

#import <DVTFoundation/DVTDeviceManager.h>
#import <DVTFoundation/DVTDeviceType.h>
#import <DVTFoundation/DVTLogAspect.h>
#import <DVTFoundation/DVTPlatform.h>

#import <IDEFoundation/IDEFoundationTestInitializer.h>

#import <FBControlCore/FBControlCore.h>

static BOOL hasLoadedFrameworks = NO;

@implementation XCTestBootstrapFrameworkLoader

#pragma mark Private

+ (BOOL)loadTestingFrameworks:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  if (hasLoadedFrameworks) {
    return YES;
  }
  if (![super loadPrivateFrameworks:logger error:error]) {
    return NO;
  }

  NSArray<FBWeakFramework *> *frameworks = @[
    FBWeakFramework.DTXConnectionServices,
    FBWeakFramework.XCTest
  ];
  BOOL success = [FBWeakFrameworkLoader loadPrivateFrameworks:frameworks logger:logger error:error];
  if (success) {
    hasLoadedFrameworks = YES;
  }
  return success;
}

+ (NSString *)loadingFrameworkName
{
  return @"XCTestBootstrap";
}

@end
