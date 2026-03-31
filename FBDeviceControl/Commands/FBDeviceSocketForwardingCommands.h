/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBDeviceCommands.h>

@class FBDevice;

/**
 The Protocol for defining socket forwarding.
 */
@protocol FBSocketForwardingCommands <FBiOSTargetCommand>

/**
 Connects to a remote port, relaying the input and output to the provided file descriptors.

 @param localFileDescriptorInput the file descriptor for the file input.
 @param localFileDescriptorOutput the file descriptor for the file output.
 @param remotePort remote port number.
 @return A future that resolves when the drain has been fully performed.
 */
- (nonnull FBFuture<NSNull *> *)drainLocalFileInput:(int)localFileDescriptorInput localFileOutput:(int)localFileDescriptorOutput remotePort:(int)remotePort;

@end

/**
 An Implementation of FBSocketForwardingCommands.
 */
@interface FBDeviceSocketForwardingCommands : NSObject <FBSocketForwardingCommands>

@end
