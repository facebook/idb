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

@implementation XCTestBootstrapFrameworkLoader

#pragma mark Public

+ (void)initializeTestingEnvironment
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    [self loadPrivateTestingFrameworksOrAbort];
  });
}


#pragma mark Private

+ (void)loadPrivateTestingFrameworksOrAbort
{
  NSArray<FBWeakFramework *> *frameworks = @[
    [FBWeakFramework DTXConnectionServices],
    [FBWeakFramework XCTest]
  ];

  NSError *error = nil;
  id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;
  if ([FBWeakFrameworkLoader loadPrivateFrameworks:frameworks logger:logger error:&error]) {
    return;
  }
  [logger.error logFormat:@"Failed to load the xcode frameworks for XCTBoostrap with error %@", error];
  abort();
}

@end
