/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <SimulatorKit/FoundationXPCProtocolProxyable-Protocol.h>
#import <Foundation/Foundation.h>

@class NSUUID;
@protocol SimDeviceIOPortDescriptorInterface;

@protocol SimDeviceIOPortInterface <FoundationXPCProtocolProxyable, NSObject>
@property (nonatomic, readonly) id<SimDeviceIOPortDescriptorInterface> descriptor;
@property (nonatomic, readonly) NSUUID *uuid;
@property (nonatomic, readonly) unsigned short ioPortClass;
@end
