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
  return [FBWeakFramework frameworkWithRelativePath:@"Library/PrivateFrameworks/CoreSimulator.framework" requiredClassNames:@[@"SimDevice"]];
}

+ (nonnull instancetype)SimulatorKit
{
  return [FBWeakFramework frameworkWithRelativePath:@"Library/PrivateFrameworks/SimulatorKit.framework" requiredClassNames:@[@"SimDeviceFramebufferService"]];
}

+ (nonnull instancetype)DTXConnectionServices
{
  return [FBWeakFramework frameworkWithRelativePath:@"../SharedFrameworks/DTXConnectionServices.framework" requiredClassNames:@[@"DTXConnection", @"DTXRemoteInvocationReceipt"]];
}

+ (nonnull instancetype)DVTFoundation
{
  return [FBWeakFramework frameworkWithRelativePath:@"../SharedFrameworks/DVTFoundation.framework" requiredClassNames:@[@"DVTDevice"]];
}

+ (nonnull instancetype)IDEFoundation
{
  return [FBWeakFramework frameworkWithRelativePath:@"../Frameworks/IDEFoundation.framework" requiredClassNames:@[@"IDEFoundationTestInitializer"]];
}

+ (nonnull instancetype)IDEiOSSupportCore
{
  return [FBWeakFramework frameworkWithRelativePath:@"../PlugIns/IDEiOSSupportCore.ideplugin"
                                 requiredClassNames:@[@"DVTiPhoneSimulator"]
                                 requiredFrameworks:@[[FBWeakFramework Xcode3Core]]];
}

+ (nonnull instancetype)Xcode3Core
{
  return [FBWeakFramework frameworkWithRelativePath:@"../PlugIns/Xcode3Core.ideplugin"];
}

+ (nonnull instancetype)XCTest
{
  return [FBWeakFramework frameworkWithRelativePath:@"Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework" requiredClassNames:@[@"XCTestConfiguration"]];
}

+ (nonnull instancetype)IBAutolayoutFoundation
{
  return [FBWeakFramework frameworkWithRelativePath:@"../Frameworks/IBAutolayoutFoundation.framework"];
}

+ (nonnull instancetype)IDEKit
{
  return [FBWeakFramework frameworkWithRelativePath:@"../Frameworks/IDEKit.framework"];
}

+ (nonnull instancetype)IDESourceEditor
{
  return [FBWeakFramework frameworkWithRelativePath:@"../PlugIns/IDESourceEditor.ideplugin"];
}

@end
