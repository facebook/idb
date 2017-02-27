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
#import <SimulatorKit/SimDeviceIOPortDescriptorState-Protocol.h>

@protocol SimDisplayDescriptorState <FoundationXPCProtocolProxyable, NSObject, SimDeviceIOPortDescriptorState>
@property (nonatomic, readonly) unsigned int defaultPixelFormat;
@property (nonatomic, readonly) unsigned int defaultHeightForDisplay;
@property (nonatomic, readonly) unsigned int defaultWidthForDisplay;
@property (nonatomic, readonly) unsigned short displayClass;
@end
