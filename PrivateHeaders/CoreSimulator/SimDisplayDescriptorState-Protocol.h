/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <CoreSimulator/FoundationXPCProtocolProxyable-Protocol.h>
#import <CoreSimulator/SimDeviceIOPortDescriptorState-Protocol.h>

@protocol SimDisplayDescriptorState <FoundationXPCProtocolProxyable, SimDeviceIOPortDescriptorState>
@property (readonly, nonatomic) unsigned int defaultPixelFormat;
@property (readonly, nonatomic) unsigned int defaultHeightForDisplay;
@property (readonly, nonatomic) unsigned int defaultWidthForDisplay;
@property (readonly, nonatomic) unsigned short displayClass;
@end
