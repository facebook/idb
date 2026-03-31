/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBAFCConnection.h>

/**
 An implementation of FBFileContainer, backed by an FBAFCConnection
 */
@interface FBDeviceFileContainer : NSObject <FBFileContainer>

/**
 The Designated Initializer.

 @param connection the connection to use.
 @param queue the queue to perform work on.
 @return a new FBDeviceFileCommands instance.
 */
- (nonnull instancetype)initWithAFCConnection:(nonnull FBAFCConnection *)connection queue:(nonnull dispatch_queue_t)queue;

@end

/**
 An implementation of FBFileCommands for Devices
 */
@interface FBDeviceFileCommands : NSObject <FBFileCommands, FBiOSTargetCommand>

#pragma mark Initializers

/**
 The Designated Initializer.

 @param target the target to use.
 @param afcCalls the calls to use.
 @return a new FBDeviceApplicationDataCommands instance.
 */
+ (nonnull instancetype)commandsWithTarget:(nonnull id<FBiOSTarget>)target afcCalls:(AFCCalls)afcCalls;

@end
