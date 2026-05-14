/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBFramebuffer;
@class FBProcessInfo;
@class FBSimulator;
@class FBSimulatorBootConfiguration;
@class FBSimulatorBridge;
@class FBSimulatorHID;

@protocol FBControlCoreLogger;

/**
 Interactions for the Lifecycle of the Simulator.
 */
@protocol FBSimulatorLifecycleCommands <NSObject, FBiOSTargetCommand, FBEraseCommands, FBPowerCommands, FBLifecycleCommands>

#pragma mark Boot/Shutdown

/**
 Boots the Simulator with the provided configuration.
 Will fail if the Simulator is currently booted.

 @param configuration the configuration to boot with.
 @return a Future that resolves when the Simulator is booted.
 */
- (FBFuture<NSNull *> *)boot:(FBSimulatorBootConfiguration *)configuration;

#pragma mark Focus

/**
 Brings the Simulator window to front, with a descriptive message in the event of a failure.

 @return A future that resolves when successful
 */
- (FBFuture<NSNull *> *)focus;

#pragma mark Connection

/**
 Disconnects from all of the underlying connection objects.
 This should be called on shutdown of the Simulator.

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

#pragma mark Bridge

/**
 Connects to the FBSimulatorHID instance.

 @return a Future Wrapping the Simulator Bridge.
 */
- (FBFuture<FBSimulatorHID *> *)connectToHID;

#pragma mark URLs

/**
 Opens the provided URL on the Simulator.

 @param url the URL to open.
 @return Future that resolves when the url is opened
 */
- (FBFuture<NSNull *> *)openURL:(NSURL *)url;

@end

/**
 The Implementation of FBSimulatorLifecycleCommands
 */
@interface FBSimulatorLifecycleCommands : NSObject <FBSimulatorLifecycleCommands>

@end

NS_ASSUME_NONNULL_END
