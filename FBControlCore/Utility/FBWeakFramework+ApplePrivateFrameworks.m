/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBWeakFramework+ApplePrivateFrameworks.h"

#import "FBControlCoreGlobalConfiguration.h"
#import "FBXcodeConfiguration.h"

@implementation FBWeakFramework (ApplePrivateFrameworks)

+ (nonnull instancetype)CoreSimulator
{
  if (FBXcodeConfiguration.isXcode9OrGreater) {
    return [FBWeakFramework frameworkWithPath:@"/Library/Developer/PrivateFrameworks/CoreSimulator.framework" requiredClassNames:@[@"SimDevice"] requiredFrameworks:@[] rootPermitted:NO];
  }
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"Library/PrivateFrameworks/CoreSimulator.framework" requiredClassNames:@[@"SimDevice"] requiredFrameworks:@[] rootPermitted:NO];
}

+ (nonnull instancetype)SimulatorKit
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"Library/PrivateFrameworks/SimulatorKit.framework" requiredClassNames:@[]  requiredFrameworks:@[] rootPermitted:NO];
}

+ (nonnull instancetype)DTXConnectionServices
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"../SharedFrameworks/DTXConnectionServices.framework" requiredClassNames:@[@"DTXConnection", @"DTXRemoteInvocationReceipt"]  requiredFrameworks:@[] rootPermitted:NO];
}

+ (nonnull instancetype)XCTest
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework" requiredClassNames:@[@"XCTestConfiguration"] requiredFrameworks:@[] rootPermitted:NO];
}

+ (instancetype)MobileDevice
{
  return [FBWeakFramework frameworkWithPath:@"/System/Library/PrivateFrameworks/MobileDevice.framework" requiredClassNames:@[] requiredFrameworks:@[] rootPermitted:YES];
}

+ (instancetype)AccessibilityPlatformTranslation
{
  return [FBWeakFramework frameworkWithPath:@"/System/Library/PrivateFrameworks/AccessibilityPlatformTranslation.framework" requiredClassNames:@[@"AXPTranslationObject"] requiredFrameworks:@[] rootPermitted:NO];
}

@end
