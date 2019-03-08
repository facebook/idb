/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
