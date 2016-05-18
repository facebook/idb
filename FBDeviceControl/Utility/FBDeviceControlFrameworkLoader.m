/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDeviceControlFrameworkLoader.h"

#import <FBControlCore/FBControlCore.h>

#import <DVTFoundation/DVTDeviceManager.h>
#import <DVTFoundation/DVTDeviceType.h>
#import <DVTFoundation/DVTLogAspect.h>
#import <DVTFoundation/DVTPlatform.h>

#import <IDEFoundation/IDEFoundationTestInitializer.h>

@implementation FBDeviceControlFrameworkLoader

+ (void)initializeFrameworks
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    [self loadPrivateFrameworksOrAbort];
    [self confirmExistenceOfClasses];
    [self initializePrincipalClasses];
  });
}

#pragma mark Private

+ (void)loadPrivateFrameworksOrAbort
{
  NSArray<FBWeakFramework *> *frameworks = @[
    FBWeakFramework.DTXConnectionServices,
    FBWeakFramework.DVTFoundation,
    FBWeakFramework.IDEFoundation,
    FBWeakFramework.IDEiOSSupportCore,
    FBWeakFramework.IBAutolayoutFoundation,
    FBWeakFramework.IDEKit,
    FBWeakFramework.IDESourceEditor,
  ];

  NSError *error = nil;
  id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;
  BOOL success = [FBWeakFrameworkLoader loadPrivateFrameworks:frameworks logger:logger error:&error];
  if (success) {
    return;
  }

  [logger.error logFormat:@"Failed to load private frameworks for FBDeviceControl with error %@", error];
  abort();
}

+ (void)confirmExistenceOfClasses
{
  NSArray<NSString *> *classNames = @[
    @"DVTDeviceManager",
    @"DVTDeviceType",
    @"DVTiOSDevice",
    @"DVTPlatform",
    @"DVTDeviceType",
  ];
  for (NSString *className in classNames) {
    Class class = NSClassFromString(className);
    NSAssert(class, @"Expected %@ to have been loaded", class);
  }
}

+ (void)initializePrincipalClasses
{
  NSError *error = nil;
  NSCAssert([NSClassFromString(@"IDEFoundationTestInitializer") initializeTestabilityWithUI:NO error:&error], @"Failed to initialize Testability %@", error);
  NSCAssert([NSClassFromString(@"DVTPlatform") loadAllPlatformsReturningError:&error], @"Failed to load all platforms: %@", error);
  NSCAssert([NSClassFromString(@"DVTPlatform") platformForIdentifier:@"com.apple.platform.iphoneos"] != nil, @"DVTPlatform hasn't been initialized yet.");
  NSCAssert([NSClassFromString(@"DVTDeviceType") deviceTypeWithIdentifier:@"Xcode.DeviceType.Mac"], @"Failed to load Xcode.DeviceType.Mac");
  NSCAssert([NSClassFromString(@"DVTDeviceType") deviceTypeWithIdentifier:@"Xcode.DeviceType.iPhone"], @"Failed to load Xcode.DeviceType.iPhone");
  [[NSClassFromString(@"DVTDeviceManager") defaultDeviceManager] startLocating];
}

@end
