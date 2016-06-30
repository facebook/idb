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

+ (void)initializeDVTEnvironment
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    // First load the Frameworks.
    [self loadPrivateDVTFrameworksOrAbort];

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


#pragma mark Private

+ (void)loadPrivateTestingFrameworksOrAbort
{
  [self loadFrameworksOrAbort:@[
    [FBWeakFramework DTXConnectionServices],
    [FBWeakFramework XCTest],
  ] groupName:@"Testing frameworks"];
}

+ (void)loadPrivateDVTFrameworksOrAbort
{
  [self loadFrameworksOrAbort:@[
    [FBWeakFramework DVTFoundation],
    [FBWeakFramework IDEFoundation],
    [FBWeakFramework IDEiOSSupportCore],
    [FBWeakFramework IBAutolayoutFoundation],
    [FBWeakFramework IDEKit],
    [FBWeakFramework IDESourceEditor]
  ] groupName:@"DVT frameworks"];
}

+ (void)loadFrameworksOrAbort:(NSArray<FBWeakFramework *> *)frameworks groupName:(NSString *)groupName
{
  NSError *error = nil;
  id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;
  if ([FBWeakFrameworkLoader loadPrivateFrameworks:frameworks logger:logger error:&error]) {
    return;
  }
  [logger.error logFormat:@"Failed to load private %@ for XCTBoostrap with error %@", groupName, error];
  abort();
}

@end
