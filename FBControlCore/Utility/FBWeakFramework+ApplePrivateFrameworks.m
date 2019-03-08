/**
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
    return [FBWeakFramework frameworkWithPath:@"/Library/Developer/PrivateFrameworks/CoreSimulator.framework" requiredClassNames:@[@"SimDevice"]];
  }
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"Library/PrivateFrameworks/CoreSimulator.framework" requiredClassNames:@[@"SimDevice"]];
}

+ (nonnull instancetype)SimulatorKit
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"Library/PrivateFrameworks/SimulatorKit.framework" requiredClassNames:@[]];
}

+ (nonnull instancetype)DTXConnectionServices
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"../SharedFrameworks/DTXConnectionServices.framework" requiredClassNames:@[@"DTXConnection", @"DTXRemoteInvocationReceipt"]];
}

+ (nonnull instancetype)XCTest
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework" requiredClassNames:@[@"XCTestConfiguration"]];
}

+ (instancetype)MobileDevice
{
  return [FBWeakFramework frameworkWithPath:@"/System/Library/PrivateFrameworks/MobileDevice.framework" requiredClassNames:@[]];
}

+ (instancetype)DeviceLink
{
  return [FBWeakFramework frameworkWithPath:@"/System/Library/PrivateFrameworks/DeviceLink.framework" requiredClassNames:@[]];
}

@end
