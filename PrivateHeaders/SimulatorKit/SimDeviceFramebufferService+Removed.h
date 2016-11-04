/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <SimulatorKit/SimDeviceFramebufferService.h>

@interface SimDeviceFramebufferService (Removed)

/**
 Removed in Xcode 8.1.
 */
- (void)suspend;
+ (id)framebufferServiceWithPort:(id)arg1 deviceDimensions:(struct CGSize)arg2 scaledDimensions:(struct CGSize)arg3 error:(id *)arg4;

@end
