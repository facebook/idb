/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBFramebuffer;
@class FBProcessInfo;
@class FBSimulator;
@class FBSimulatorBootConfiguration;
@class FBSimulatorConnection;

@protocol FBControlCoreLogger;

/**
 Interactions for the Lifecycle of the Simulator.
 */
@protocol FBSimulatorLifecycleCommands <NSObject>

#pragma mark Boot/Shutdown

/**
 Boots the Simulator with the default Simulator Launch Configuration.
 Will fail if the Simulator is currently booted.

 @param error an error out for any error that occurs.
 @return the reciever, for chaining.
 */
- (BOOL)bootSimulatorWithError:(NSError **)error;

/**
 Boots the Simulator with the default Simulator Launch Configuration.
 Will fail if the Simulator is currently booted.

 @param error an error out for any error that occurs.
 @return the reciever, for chaining.
 */
- (BOOL)bootSimulator:(FBSimulatorBootConfiguration *)configuration error:(NSError **)error;

/**
 Shuts the Simulator down.
 Will fail if the Simulator is not booted.

 @param error an error out for any error that occurs.
 @return the reciever, for chaining.
 */
- (BOOL)shutdownSimulatorWithError:(NSError **)error;

#pragma mark Connection

/**
 Connects to the FBSimulatorConnection.

 @param error an error out for any error that occurs.
 @return the Simulator Connection on success, nil otherwise.
 */
- (nullable FBSimulatorConnection *)connectWithError:(NSError **)error;

/**
 Disconnects from FBSimulatorConnection.

 @param timeout the timeout in seconds to wait for all connected components to disconnect.
 @param logger a logger to log to
 @param error an error for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)disconnectWithTimeout:(NSTimeInterval)timeout logger:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error;

#pragma mark Framebuffer

/**
 Obtains the Framebuffer.

 @param error an error out for any error that occurs.
 @return the Framebuffer on success, nil otherwise.
 */
- (nullable FBFramebuffer *)framebufferWithError:(NSError **)error;

#pragma mark URLs

/**
 Opens the provided URL on the Simulator.

 @param url the URL to open.
 @param error an error out for any error that occurs.
 @return the reciever, for chaining.
 */
- (BOOL)openURL:(NSURL *)url error:(NSError **)error;

#pragma mark Subprocesses

/**
 Terminates a Subprocess of the Simulator.

 @param process the process to terminate.
 @param error an error out for any error that occurs.
 @return the reciever, for chaining.
 */
- (BOOL)terminateSubprocess:(FBProcessInfo *)process error:(NSError **)error;

@end

/**
 The Implementation of FBSimulatorLifecycleCommands
 */
@interface FBSimulatorLifecycleCommands : NSObject <FBSimulatorLifecycleCommands>

/**
 The Designated Intializer

 @param simulator the Simulator.
 @return a new Simulator Lifecycle Commands Instance.
 */
+ (instancetype)commandsWithSimulator:(FBSimulator *)simulator;

@end

NS_ASSUME_NONNULL_END
