/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <AppKit/NSPasteboardItem.h>

/**
 Removed from CoreSimulator as of Xcode 27 (CoreSimulator 1155.4): part of the simulator pasteboard / clipboard sync subsystem. No longer
 present in any Xcode 27 framework and not referenced by idb/FBSimulatorControl.
 Header retained for reference and for building against <= Xcode 26.x; scheduled
 for removal.
 */
@interface NSPasteboardItem (SimPasteboardItem)
- (void)resolveAllTypes;
- (BOOL)setSimPBItemValue:(id)arg1 forType:(id)arg2;
@end
