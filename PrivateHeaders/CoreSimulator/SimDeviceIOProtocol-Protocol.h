/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class NSArray, NSObject, NSUUID;
@protocol SimDeviceIOPortConsumer, SimDeviceIOPortInterface;

@protocol SimDeviceIOProtocol <NSObject>
- (void)detachConsumer:(NSObject<SimDeviceIOPortConsumer> *)arg1 fromPort:(NSObject<SimDeviceIOPortInterface> *)arg2;
- (void)attachConsumer:(NSObject<SimDeviceIOPortConsumer> *)arg1 toPort:(NSObject<SimDeviceIOPortInterface> *)arg2;
- (NSArray<SimDeviceIOPortInterface> *)ioPorts;
- (NSObject<SimDeviceIOPortInterface> *)ioPortForUUID:(NSUUID *)arg1;
@end
