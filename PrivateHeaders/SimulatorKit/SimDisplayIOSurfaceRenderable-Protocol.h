/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <SimulatorKit/FoundationXPCProtocolProxyable-Protocol.h>

@protocol SimDisplayIOSurfaceRenderable <FoundationXPCProtocolProxyable>

/**
 In Xcode 8, this is an xpc_object_t
 In Xcode 9, this is an IOSurfaceRef.
 Consumers should take this into account.
 */
@property (readonly, nullable, nonatomic) id ioSurface;

@end
