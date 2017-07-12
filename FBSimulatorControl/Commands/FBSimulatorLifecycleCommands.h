/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

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
- (BOOL)bootWithError:(NSError **)error;

/**
 Boots the Simulator with the default Simulator Launch Configuration.
 Will fail if the Simulator is currently booted.

 @param error an error out for any error that occurs.
 @return the reciever, for chaining.
 */
- (BOOL)boot:(FBSimulatorBootConfiguration *)configuration error:(NSError **)error;

/**
 Shuts the Simulator down.
 Will fail if the Simulator is not booted.

 @param error an error out for any error that occurs.
 @return the reciever, for chaining.
 */
- (BOOL)shutdownWithError:(NSError **)error;

#pragma mark Erase

/**
 Calls `freeSimulator:error:` on this device's pool, with the reciever as the first argument.

 @param error an error out for any error that occured.
 @returns YES if the freeing of the device was successful, NO otherwise.
 */
- (BOOL)freeFromPoolWithError:(NSError **)error;

/**
 Erases the Simulator, with a descriptive message in the event of a failure.

 @param error a descriptive error for any error that occurred.
 @return YES if successful, NO otherwise.
 */
- (BOOL)eraseWithError:(NSError **)error;

#pragma mark States

/**
 Synchronously waits on the provided state.

 @param state the state to wait on
 @returns YES if the Simulator transitioned to the given state with the default timeout, NO otherwise
 */
- (BOOL)waitOnState:(FBSimulatorState)state;

/**
 Synchronously waits on the provided state.

 @param state the state to wait on
 @param timeout timeout
 @returns YES if the Simulator transitioned to the given state with the timeout, NO otherwise
 */
- (BOOL)waitOnState:(FBSimulatorState)state timeout:(NSTimeInterval)timeout;

/**
 A Synchronous wait, with a default timeout, producing a meaningful error message.

 @param state the state to wait on
 @param error an error out for a timeout error if one occurred
 @returns YES if the Simulator transitioned to the given state with the timeout, NO otherwise
 */
- (BOOL)waitOnState:(FBSimulatorState)state error:(NSError **)error;

#pragma mark Focus

/**
 Brings the Simulator window to front, with a descriptive message in the event of a failure.

 @param error a descriptive error for any error that occurred.
 @return YES if successful, NO otherwise.
 */
- (BOOL)focusWithError:(NSError **)error;

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
