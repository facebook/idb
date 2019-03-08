/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/FoundationXPCProtocolProxyable-Protocol.h>
#import <CoreSimulator/SimDeviceIOPortDescriptorState-Protocol.h>

@protocol SimDisplayDescriptorState <FoundationXPCProtocolProxyable, SimDeviceIOPortDescriptorState>
@property (readonly, nonatomic) unsigned int defaultPixelFormat;
@property (readonly, nonatomic) unsigned int defaultHeightForDisplay;
@property (readonly, nonatomic) unsigned int defaultWidthForDisplay;
@property (readonly, nonatomic) unsigned short displayClass;
@end
