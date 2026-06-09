/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimDeviceNotifier-Protocol.h>

@class NSArray, NSObject;
@protocol OS_dispatch_queue;

/**
 Removed from CoreSimulator as of Xcode 27 (CoreSimulator 1155.4): part of the simulator pasteboard / clipboard sync subsystem. No longer
 present in any Xcode 27 framework and not referenced by idb/FBSimulatorControl.
 Header retained for reference and for building against <= Xcode 26.x; scheduled
 for removal.
 */
@protocol SimPasteboard <SimDeviceNotifier>
@property (atomic, readonly, copy) NSArray *items;
@property (atomic, readonly) unsigned long long changeCount;
- (void)setPasteboardAsyncWithItems:(NSArray *)arg1 completionQueue:(NSObject<OS_dispatch_queue> *)arg2 completionHandler:(void (^)(unsigned long long, NSError *))arg3;
- (unsigned long long)setPasteboardWithItems:(NSArray *)arg1 error:(id *)arg2;
@end
