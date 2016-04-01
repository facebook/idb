/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFoundationInitializer.h"

#import <DVTFoundation/DVTDeviceManager.h>
#import <DVTFoundation/DVTDeviceType.h>
#import <DVTFoundation/DVTLogAspect.h>
#import <DVTFoundation/DVTPlatform.h>

#import <IDEFoundation/IDEFoundationTestInitializer.h>

@implementation FBFoundationInitializer

+ (void)initializeTestingEnvironment
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSError *error = nil;
    NSAssert([NSClassFromString(@"IDEFoundationTestInitializer") initializeTestabilityWithUI:NO error:&error], @"Failed to initialize Testability %@", error);
    NSAssert([NSClassFromString(@"DVTPlatform") loadAllPlatformsReturningError:&error], @"Failed to load all platforms: %@", error);
    NSAssert([NSClassFromString(@"DVTPlatform") platformForIdentifier:@"com.apple.platform.iphoneos"] != nil, @"DVTPlatform hasn't been initialized yet.");
    NSAssert([NSClassFromString(@"DVTDeviceType") deviceTypeWithIdentifier:@"Xcode.DeviceType.Mac"], @"Failed to load Xcode.DeviceType.Mac");
    NSAssert([NSClassFromString(@"DVTDeviceType") deviceTypeWithIdentifier:@"Xcode.DeviceType.iPhone"], @"Failed to load Xcode.DeviceType.iPhone");
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

@end
