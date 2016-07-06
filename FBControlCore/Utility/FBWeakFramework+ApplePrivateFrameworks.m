/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBWeakFramework+ApplePrivateFrameworks.h"

@implementation FBWeakFramework (ApplePrivateFrameworks)

+ (nonnull instancetype)CoreSimulator
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"Library/PrivateFrameworks/CoreSimulator.framework" requiredClassNames:@[@"SimDevice"]];
}

+ (nonnull instancetype)SimulatorKit
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"Library/PrivateFrameworks/SimulatorKit.framework" requiredClassNames:@[@"SimDeviceFramebufferService"]];
}

+ (nonnull instancetype)DTXConnectionServices
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"../SharedFrameworks/DTXConnectionServices.framework" requiredClassNames:@[@"DTXConnection", @"DTXRemoteInvocationReceipt"]];
}

+ (nonnull instancetype)DVTFoundation
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"../SharedFrameworks/DVTFoundation.framework" requiredClassNames:@[@"DVTDevice"]];
}

+ (nonnull instancetype)IDEFoundation
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"../Frameworks/IDEFoundation.framework" requiredClassNames:@[@"IDEFoundationTestInitializer"]];
}

+ (nonnull instancetype)IDEiOSSupportCore
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"../PlugIns/IDEiOSSupportCore.ideplugin"
    requiredClassNames:@[@"DVTiPhoneSimulator"]
    requiredFrameworks:@[
      FBWeakFramework.DevToolsFoundation,
      FBWeakFramework.DevToolsSupport,
      FBWeakFramework.DevToolsCore,
  ]];
}

+ (nonnull instancetype)DevToolsFoundation
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"../PlugIns/Xcode3Core.ideplugin/Contents/Frameworks/DevToolsFoundation.framework"];
}

+ (nonnull instancetype)DevToolsSupport
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"../PlugIns/Xcode3Core.ideplugin/Contents/Frameworks/DevToolsSupport.framework"];
}

+ (nonnull instancetype)DevToolsCore
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"../PlugIns/Xcode3Core.ideplugin/Contents/Frameworks/DevToolsCore.framework"];
}

+ (nonnull instancetype)XCTest
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework" requiredClassNames:@[@"XCTestConfiguration"]];
}

+ (nonnull instancetype)IBAutolayoutFoundation
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"../Frameworks/IBAutolayoutFoundation.framework"];
}

+ (nonnull instancetype)IDEKit
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"../Frameworks/IDEKit.framework"];
}

+ (nonnull instancetype)IDESourceEditor
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"../PlugIns/IDESourceEditor.ideplugin"];
}

+ (instancetype)ConfigurationUtilityKit
{
  return [FBWeakFramework
    appleConfigurationFrameworkWithRelativePath:@"Contents/Frameworks/ConfigurationUtilityKit.framework"
    requiredClassNames:@[@"MDKMobileDevice"]
    requiredFrameworks:@[
      FBWeakFramework.ConfigurationProfile,
    ]];
}

+ (instancetype)ConfigurationProfile
{
  return [FBWeakFramework appleConfigurationFrameworkWithRelativePath:@"Contents/Frameworks/ConfigurationProfile.framework" requiredClassNames:@[]];
}

+ (instancetype)MobileDevice
{
  return [FBWeakFramework frameworkWithPath:@"/System/Library/PrivateFrameworks/MobileDevice.framework" requiredClassNames:@[]];
}

@end
