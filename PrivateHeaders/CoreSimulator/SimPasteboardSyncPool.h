/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
