/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 Removed from CoreSimulator as of Xcode 27 (CoreSimulator 1155.4): the secure-archiving helpers used by the removed pasteboard subsystem. No longer
 present in any Xcode 27 framework and not referenced by idb/FBSimulatorControl.
 Header retained for reference and for building against <= Xcode 26.x; scheduled
 for removal.
 */
@interface NSKeyedArchiver (SimSecurely)
+ (id)sim_securelyArchivedDataWithRootObject:(id)arg1;
@end
