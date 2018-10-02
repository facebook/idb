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
@class FBSimulatorBridge;
@class FBSimulatorConnection;
@class FBSimulatorHID;

@protocol FBControlCoreLogger;

/**
 Interactions for the Lifecycle of the Simulator.
 */
@protocol FBSimulatorLifecycleCommands <NSObject, FBiOSTargetCommand>

#pragma mark Boot/Shutdown

/**
 Boots the Simulator with the default Simulator Launch Configuration.
 Will fail if the Simulator is currently booted.

 @return a Future that resolves when the Simulator is booted.
 */
- (FBFuture<NSNull *> *)boot;

/**
 Boots the Simulator with the default Simulator Launch Configuration.
 Will fail if the Simulator is currently booted.

 @param configuration the configuration to boot with.
 @return a Future that resolves when the Simulator is booted.
 */
- (FBFuture<NSNull *> *)bootWithConfiguration:(FBSimulatorBootConfiguration *)configuration;

/**
 Shuts the Simulator down.
 Will fail if the Simulator is not booted.

 @return a Future that resolves when the Simulator has shutdown booted.
 */
- (FBFuture<NSNull *> *)shutdown;

#pragma mark Erase

/**
 Calls `freeSimulator` on this device's pool, with the reciever as the first argument.

 @return A future that resolves when freed.
 */
- (FBFuture<NSNull *> *)freeFromPool;

/**
 Erases the Simulator, with a descriptive message in the event of a failure.

 @return a Future that resolves when the Simulator has been erased.
 */
- (FBFuture<NSNull *> *)erase;

#pragma mark States

/**
 Asynchronously waits on the provided state.

 @param state the state to wait on
 @return A future that resolves when it has transitioned to the given state.
 */
- (FBFuture<NSNull *> *)resolveState:(FBiOSTargetState)state;

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

 @return A Future wrapping the the Simulator Connection.
 */
- (FBFuture<FBSimulatorConnection *> *)connect;

/**
 Connects to the FBSimulatorConnection, using existing values.

 @param hid the hid to connect.
 @param framebuffer the framebuffer to connect.
 @return A Future wrapping the the Simulator Connection.
 */
- (FBFuture<FBSimulatorConnection *> *)connectWithHID:(nullable FBSimulatorHID *)hid framebuffer:(nullable FBFramebuffer *)framebuffer;

/**
 Disconnects from FBSimulatorConnection.

 @param timeout the timeout in seconds to wait for all connected components to disconnect.
 @param logger a logger to log to
 @return YES if successful, NO otherwise.
 */
- (FBFuture<NSNull *> *)disconnectWithTimeout:(NSTimeInterval)timeout logger:(nullable id<FBControlCoreLogger>)logger;

#pragma mark Bridge

/**
 Connects to the FBSimulatorBridge.

 @return a Future Wrapping the Simulator Bridge.
 */
- (FBFuture<FBSimulatorBridge *> *)connectToBridge;

#pragma mark Framebuffer

/**
 Connects to the Framebuffer.

 @return the Future wrapping the Framebuffer.
 */
- (FBFuture<FBFramebuffer *> *)connectToFramebuffer;

#pragma mark URLs

/**
 Opens the provided URL on the Simulator.

 @param url the URL to open.
 @param error an error out for any error that occurs.
 @return the reciever, for chaining.
 */
- (BOOL)openURL:(NSURL *)url error:(NSError **)error;

@end

/**
 The Implementation of FBSimulatorLifecycleCommands
 */
@interface FBSimulatorLifecycleCommands : NSObject <FBSimulatorLifecycleCommands>

@end

NS_ASSUME_NONNULL_END
