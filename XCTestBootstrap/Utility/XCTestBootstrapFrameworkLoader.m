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
    // First load the Frameworks.
    [self loadPrivateFrameworksOrAbort];

    // Then confirm the important classes exist.
    NSError *error = nil;
    NSCAssert([NSClassFromString(@"IDEFoundationTestInitializer") initializeTestabilityWithUI:NO error:&error], @"Failed to initialize Testability %@", error);
    NSCAssert([NSClassFromString(@"DVTPlatform") loadAllPlatformsReturningError:&error], @"Failed to load all platforms: %@", error);
    NSCAssert([NSClassFromString(@"DVTPlatform") platformForIdentifier:@"com.apple.platform.iphoneos"] != nil, @"DVTPlatform hasn't been initialized yet.");
    NSCAssert([NSClassFromString(@"DVTDeviceType") deviceTypeWithIdentifier:@"Xcode.DeviceType.Mac"], @"Failed to load Xcode.DeviceType.Mac");
    NSCAssert([NSClassFromString(@"DVTDeviceType") deviceTypeWithIdentifier:@"Xcode.DeviceType.iPhone"], @"Failed to load Xcode.DeviceType.iPhone");
    [[NSClassFromString(@"DVTDeviceManager") defaultDeviceManager] startLocating];
  });
}

+ (void)enableDebugLogging
{
  [[NSClassFromString(@"DVTLogAspect") logAspectWithName:@"iPhoneSupport"] setLogLevel:10];
  [[NSClassFromString(@"DVTLogAspect") logAspectWithName:@"iPhoneSimulator"] setLogLevel:10];
  [[NSClassFromString(@"DVTLogAspect") logAspectWithName:@"DVTDevice"] setLogLevel:10];
  [[NSClassFromString(@"DVTLogAspect") logAspectWithName:@"Operations"] setLogLevel:10];
  [[NSClassFromString(@"DVTLogAspect") logAspectWithName:@"Executable"] setLogLevel:10];
  [[NSClassFromString(@"DVTLogAspect") logAspectWithName:@"CommandInvocation"] setLogLevel:10];
}

#pragma mark Private

+ (void)loadPrivateFrameworksOrAbort
{
  NSArray<FBWeakFramework *> *frameworks = @[
    [FBWeakFramework DTXConnectionServices],
    [FBWeakFramework DVTFoundation],
    [FBWeakFramework IDEFoundation],
    [FBWeakFramework IDEiOSSupportCore],
    [FBWeakFramework XCTest],
    [FBWeakFramework IBAutolayoutFoundation],
    [FBWeakFramework IDEKit],
    [FBWeakFramework IDESourceEditor],
  ];

  NSError *error = nil;
  id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;
  BOOL success = [FBWeakFrameworkLoader loadPrivateFrameworks:frameworks logger:logger error:&error];
  if (success) {
    return;
  }
  [logger.error logFormat:@"Failed to load private frameworks for XCTBoostrap with error %@", error];
  abort();
}

@end
