/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 As of Xcode 27 (CoreSimulator 1155.4) this category is implemented in
 CoreSimulatorUtilities (CoreSimulator.framework/Frameworks/CoreSimulatorUtilities),
 which CoreSimulator hard-links via LC_LOAD_DYLIB, so +simulatorDefaults still
 registers in the ObjC runtime whenever CoreSimulator loads.
 FBSimulatorControlFrameworkLoader calls it (guarded by -respondsToSelector:) to
 toggle CoreSimulator debug logging, so this remains functional under Xcode 27.
 */
@interface NSUserDefaults (SimDefaults)
+ (id)simulatorDefaults;
@end
