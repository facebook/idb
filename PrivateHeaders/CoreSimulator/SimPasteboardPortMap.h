/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class NSMutableDictionary;
@protocol OS_dispatch_queue;

@interface SimPasteboardPortMap : NSObject
{
    NSMutableDictionary *_portToProxyMap;
    NSObject<OS_dispatch_queue> *_concurrentQueue;
}

+ (id)sharedManager;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *concurrentQueue;
@property (retain, nonatomic) NSMutableDictionary *portToProxyMap;

- (id)createPortKey:(unsigned int)arg1;
- (void)setValue:(id)arg1 forPort:(unsigned int)arg2;
- (id)lookupWith:(unsigned int)arg1;
- (id)description;
- (id)init;

@end
