/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBControlCore/FBWeakFramework.h>

/**
 Creates FBWeakFrameworks that represents Apple's private frameworks with paths relative to developer directory (pointed by `xcode-select -p`).
 */
@interface FBWeakFramework (ApplePrivateFrameworks)

+ (nonnull instancetype)CoreSimulator;
+ (nonnull instancetype)SimulatorKit;
+ (nonnull instancetype)DVTiPhoneSimulatorRemoteClient;
+ (nonnull instancetype)DTXConnectionServices;
+ (nonnull instancetype)DVTFoundation;
+ (nonnull instancetype)IDEFoundation;
+ (nonnull instancetype)IDEiOSSupportCore;

/**
 XCTest framework for MacOSX
 */
+ (nonnull instancetype)XCTest;

@end
