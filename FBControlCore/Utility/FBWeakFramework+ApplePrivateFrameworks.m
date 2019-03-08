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

+ (nonnull instancetype)DFRSupportKit
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"../Frameworks/DFRSupportKit.framework"];
}

+ (nonnull instancetype)DVTKit
{
  return [FBWeakFramework xcodeFrameworkWithRelativePath:@"../SharedFrameworks/DVTKit.framework"];
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
