/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

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
@protocol FBSimulatorLifecycleCommandsProtocol <NSObject, FBiOSTargetCommand, FBEraseCommands, FBPowerCommands, FBLifecycleCommands>

#pragma mark Boot/Shutdown

- (nonnull FBFuture<NSNull *> *)boot:(nonnull FBSimulatorBootConfiguration *)configuration;

#pragma mark Focus

- (nonnull FBFuture<NSNull *> *)focus;

#pragma mark Connection

- (nonnull FBFuture<NSNull *> *)disconnectWithTimeout:(NSTimeInterval)timeout logger:(nullable id<FBControlCoreLogger>)logger;

#pragma mark Bridge

- (nonnull FBFuture<FBSimulatorBridge *> *)connectToBridge;

#pragma mark Framebuffer

- (nonnull FBFuture<FBFramebuffer *> *)connectToFramebuffer;

#pragma mark HID

- (nonnull FBFuture<FBSimulatorHID *> *)connectToHID;

#pragma mark URLs

- (nonnull FBFuture<NSNull *> *)openURL:(nonnull NSURL *)url;

@end

// FBSimulatorLifecycleCommands class is now implemented in Swift.
// The Swift header is imported by the umbrella header FBSimulatorControl.h.
