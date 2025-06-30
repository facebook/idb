/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBWeakFramework+ApplePrivateFrameworks.h"

#import "FBControlCoreGlobalConfiguration.h"
#import "FBXcodeConfiguration.h"

@implementation FBWeakFramework (ApplePrivateFrameworks)

+ (instancetype)CoreSimulator
{
  return [FBWeakFramework frameworkWithPath:@"/Library/Developer/PrivateFrameworks/CoreSimulator.framework" requiredClassNames:@[@"SimDevice"] rootPermitted:NO];
}

+ (instancetype)SimulatorKit
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"Library/PrivateFrameworks/SimulatorKit.framework" requiredClassNames:@[]];
}

+ (instancetype)DTXConnectionServices
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"../SharedFrameworks/DTXConnectionServices.framework" requiredClassNames:@[@"DTXConnection", @"DTXRemoteInvocationReceipt"]];
}

+ (instancetype)XCTest
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework" requiredClassNames:@[@"XCTestConfiguration"]];
}

+ (instancetype)MobileDevice
{
  return [FBWeakFramework frameworkWithPath:@"/System/Library/PrivateFrameworks/MobileDevice.framework" requiredClassNames:@[] rootPermitted:YES];
}

+ (instancetype)AccessibilityPlatformTranslation
{
  return [FBWeakFramework frameworkWithPath:@"/System/Library/PrivateFrameworks/AccessibilityPlatformTranslation.framework" requiredClassNames:@[@"AXPTranslationObject"] rootPermitted:NO];
}

@end
