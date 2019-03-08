/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class NSArray, NSUUID;
@protocol SimDeviceIOPortConsumer, SimDeviceIOPortInterface;

@protocol SimDeviceIOProtocol <NSObject>
- (void)detachConsumer:(id<SimDeviceIOPortConsumer>)arg1 fromPort:(id<SimDeviceIOPortInterface>)arg2;
- (void)attachConsumer:(id<SimDeviceIOPortConsumer>)arg1 toPort:(id<SimDeviceIOPortInterface>)arg2;
- (id<SimDeviceIOPortInterface>)ioPortForUUID:(NSUUID *)arg1;
- (NSArray *)ioPorts;
@end
