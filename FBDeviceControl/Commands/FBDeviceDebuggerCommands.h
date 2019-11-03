/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAMDServiceConnection;
@class FBDevice;

/**
 Implementations of debugger related commands.
 */
@interface FBDeviceDebuggerCommands : NSObject <FBDebuggerCommands>

#pragma mark Initializers

/**
 Instantiates the Commands instance.

 @param target the target to use.
 @return a new instance of the Command.
 */
+ (instancetype)commandsWithTarget:(FBDevice *)target;

#pragma mark Public Methods

/**
 Starts the Debug Server and exposes it via a service connection.

 @return a future context with the service connection to the debug server.
 */
- (FBFutureContext<FBAMDServiceConnection *> *)connectToDebugServer;

@end

NS_ASSUME_NONNULL_END
