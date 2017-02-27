/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
