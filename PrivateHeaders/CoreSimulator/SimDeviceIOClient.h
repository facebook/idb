/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <CoreSimulator/SimDeviceIO.h>

@class NSArray, NSMutableDictionary, NSObject;
@protocol OS_dispatch_queue;

@interface SimDeviceIOClient : SimDeviceIO
{
    NSArray *_deviceIOPorts;
    struct NSMutableDictionary *_consumerProxies;
    NSObject<OS_dispatch_queue> *_executionQueue;
}

@property (retain, nonatomic) NSObject<OS_dispatch_queue> *executionQueue;
@property (retain, nonatomic) NSMutableDictionary *consumerProxies;
@property (nonatomic, copy) NSArray *deviceIOPorts;

- (void)updateIOPorts;
- (void)detachConsumerUUID:(id)arg1 fromPort:(id)arg2;
- (void)detachConsumer:(id)arg1 fromPort:(id)arg2;
- (void)attachConsumer:(id)arg1 toPort:(id)arg2;
- (id)ioPorts;
- (void)dealloc;
- (id)initWithDevice:(id)arg1;

@end
