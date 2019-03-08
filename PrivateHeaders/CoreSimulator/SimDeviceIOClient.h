/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
- (void)detachConsumer:(id)arg1 fromPort:(id)arg2;
- (id)ioPorts;
- (void)dealloc;
- (id)initWithDevice:(id)arg1;

@end
