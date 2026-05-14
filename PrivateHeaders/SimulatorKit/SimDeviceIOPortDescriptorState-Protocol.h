/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <SimulatorKit/FoundationXPCProtocolProxyable-Protocol.h>

@protocol SimDeviceIOPortDescriptorState <FoundationXPCProtocolProxyable, NSObject>
@property (nonatomic, readonly) int powerState;
@end
