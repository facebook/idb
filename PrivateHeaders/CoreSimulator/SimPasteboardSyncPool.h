/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <objc/NSObject.h>

#import <CoreSimulator/SimPasteboardSyncPoolProtocol-Protocol.h>

@class NSMapTable, NSUUID;
@protocol OS_dispatch_queue;

/**
 Removed from CoreSimulator as of Xcode 27 (CoreSimulator 1155.4): part of the simulator pasteboard / clipboard sync subsystem. No longer
 present in any Xcode 27 framework and not referenced by idb/FBSimulatorControl.
 Header retained for reference and for building against <= Xcode 26.x; scheduled
 for removal.
 */
@interface SimPasteboardSyncPool : NSObject <SimPasteboardSyncPoolProtocol>
{
  NSMapTable *_pasteboards;
  NSObject<OS_dispatch_queue> *_processing_queue;
  NSUUID *_poolIdentifier;
}

@property (nonatomic, retain) NSUUID *poolIdentifier;
@property (nonatomic, retain) NSObject<OS_dispatch_queue> *processing_queue;
@property (nonatomic, retain) NSMapTable *pasteboards;
- (void)unregisterAndRemoveAll;
- (BOOL)removePasteboard:(id)arg1 withError:(id *)arg2;
- (BOOL)addPasteboard:(id)arg1 withError:(id *)arg2;
- (void)dealloc;
- (id)init;

@end
