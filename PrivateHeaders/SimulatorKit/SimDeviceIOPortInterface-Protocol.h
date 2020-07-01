/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <SimulatorKit/FoundationXPCProtocolProxyable-Protocol.h>
#import <Foundation/Foundation.h>

@class NSUUID;

@protocol SimDeviceIOPortInterface <FoundationXPCProtocolProxyable, NSObject>
@property (nonatomic, readonly) id descriptor;
@property (nonatomic, readonly) NSUUID *uuid;
@property (nonatomic, readonly) unsigned short ioPortClass;
@end
