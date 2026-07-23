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
 which CoreSimulator hard-links via LC_LOAD_DYLIB, so these methods register in the
 ObjC runtime whenever CoreSimulator loads — behavior unchanged. Declaration
 retained here. Not referenced by idb/FBSimulatorControl.
 */
@interface NSString (SIMPackedVersion)
+ (id)sim_stringForPackedVersion:(unsigned int)arg1;
- (unsigned int)sim_packedVersion;
@end
