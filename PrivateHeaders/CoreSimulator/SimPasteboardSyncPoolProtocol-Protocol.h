/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@class NSObject, NSUUID;
@protocol SimPasteboard;

/**
 Removed from CoreSimulator as of Xcode 27 (CoreSimulator 1155.4): part of the simulator pasteboard / clipboard sync subsystem. No longer
 present in any Xcode 27 framework and not referenced by idb/FBSimulatorControl.
 Header retained for reference and for building against <= Xcode 26.x; scheduled
 for removal.
 */
@protocol SimPasteboardSyncPoolProtocol
@property (nonatomic, readonly, retain) NSUUID *poolIdentifier;
- (BOOL)removePasteboard:(NSObject<SimPasteboard> *)arg1 withError:(id *)arg2;
- (BOOL)addPasteboard:(NSObject<SimPasteboard> *)arg1 withError:(id *)arg2;
@end
