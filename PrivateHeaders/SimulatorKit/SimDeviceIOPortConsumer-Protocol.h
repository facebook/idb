/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <SimulatorKit/FoundationXPCProtocolProxyable-Protocol.h>

@class NSString, NSUUID;

@protocol SimDeviceIOPortConsumer <FoundationXPCProtocolProxyable>
@property (readonly, nonatomic) NSUUID *consumerUUID;
@property (nonatomic, copy, readonly) NSString *consumerIdentifier;
@end
