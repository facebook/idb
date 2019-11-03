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

/**
 A Debug Server for Devices.
 This class acts as the relay between a public TCP port and the service connection for the device we are talking to.
 */
@interface FBDeviceDebugServer : NSObject <FBDebugServer>

#pragma mark Initializers

/**
 The Designated Initializer.

 @param service a FBFutureContext that yields a FBAMDServiceConnection for the debug server.
 @param port the port to bind on.
 @param lldbBootstrapCommands the lldb commands.
 @param queue the queue to serialize work on.
 @param logger the logger to log to.
 @return A future that resolves with the debug server instance.
 */
+ (FBFuture<FBDeviceDebugServer *> *)debugServerForServiceConnection:(FBFutureContext<FBAMDServiceConnection *> *)service port:(in_port_t)port lldbBootstrapCommands:(NSArray<NSString *> *)lldbBootstrapCommands queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
