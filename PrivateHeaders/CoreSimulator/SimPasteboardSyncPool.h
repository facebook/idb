/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <objc/NSObject.h>

#import <CoreSimulator/SimPasteboardSyncPoolProtocol-Protocol.h>

@class NSMapTable, NSUUID;
@protocol OS_dispatch_queue;

@interface SimPasteboardSyncPool : NSObject <SimPasteboardSyncPoolProtocol>
{
    NSMapTable *_pasteboards;
    NSObject<OS_dispatch_queue> *_processing_queue;
    NSUUID *_poolIdentifier;
}

@property (retain, nonatomic) NSUUID *poolIdentifier;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *processing_queue;
@property (retain, nonatomic) NSMapTable *pasteboards;
- (void).cxx_destruct;
- (void)unregisterAndRemoveAll;
- (BOOL)removePasteboard:(id)arg1 withError:(id *)arg2;
- (BOOL)addPasteboard:(id)arg1 withError:(id *)arg2;
- (void)dealloc;
- (id)init;

@end
