/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class NSMutableDictionary;
@protocol OS_dispatch_queue;

/**
 Removed from CoreSimulator as of Xcode 27 (CoreSimulator 1155.4): part of the simulator pasteboard / clipboard sync subsystem. No longer
 present in any Xcode 27 framework and not referenced by idb/FBSimulatorControl.
 Header retained for reference and for building against <= Xcode 26.x; scheduled
 for removal.
 */
@interface SimPasteboardPortMap : NSObject
{
  NSMutableDictionary *_portToProxyMap;
  NSObject<OS_dispatch_queue> *_concurrentQueue;
}

+ (id)sharedManager;
@property (nonatomic, retain) NSObject<OS_dispatch_queue> *concurrentQueue;
@property (nonatomic, retain) NSMutableDictionary *portToProxyMap;

- (id)createPortKey:(unsigned int)arg1;
- (void)setValue:(id)arg1 forPort:(unsigned int)arg2;
- (id)lookupWith:(unsigned int)arg1;
- (id)description;
- (id)init;

@end
