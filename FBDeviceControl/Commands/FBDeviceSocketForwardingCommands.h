/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@protocol FBSocketForwardingCommands <FBiOSTargetCommand>

- (nonnull FBFuture<NSNull *> *)drainLocalFileInput:(int)localFileDescriptorInput localFileOutput:(int)localFileDescriptorOutput remotePort:(int)remotePort;

@end
