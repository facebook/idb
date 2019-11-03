/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBApplicationLaunchConfiguration;
@class FBFramebuffer;
@class FBSimulator;
@class FBSimulatorBootConfiguration;
@class FBSimulatorBridge;
@class FBSimulatorHID;

NS_ASSUME_NONNULL_BEGIN

/**
 A Simulator Connection is a container for all of the relevant services that can be obtained when launching via: -[SimDevice bootWithOptions:error].
 Typically these are all the services with which Simulator.app can interact with, except that we have them inside FBSimulatorControl.

 The Constructor takes arguments that are a product of the booting process. These arguments *must* be provided when the connection is established.
 These arguments can be nil, but will not change during the lifetime of a connection.
 The 'Simulator Bridge' connection can be established lazily, that is to say the Bridge Connection can be made *after* the connection is created.
 */
@interface FBSimulatorConnection : NSObject  <FBJSONSerializable>

#pragma mark Initializers

/**
 The Designated Initializer.

 @param simulator the Simulator to Connect to.
 @param framebuffer the Framebuffer. May be nil.
 @param hid the Indigo HID Port. May be nil.
 */
- (instancetype)initWithSimulator:(FBSimulator *)simulator framebuffer:(nullable FBFramebuffer *)framebuffer hid:(nullable FBSimulatorHID *)hid;

#pragma mark Connection Lifecycle

/**
 Tears down the bridge and it's resources.
 If there is any asynchronous work that is pending, it will resolve the returned future upon completion.

 @return A Future that resolves when the connection has been terminated.
 */
- (FBFuture<NSNull *> *)terminate;

/**
 Connects to the FBSimulatorBridge.

 @return a Future wrapping the Bridge Instance if successful, nil otherwise.
 */
- (FBFuture<FBSimulatorBridge *> *)connectToBridge;

/**
 Connects to the Framebuffer's Surface.

 @return a Future that resolves with the Framebuffer instance.
 */
- (FBFuture<FBFramebuffer *> *)connectToFramebuffer;

/**
 Connects to the FBSimulatorHID.

 @return the HID instance if successful, nil otherwise.
 */
- (FBFuture<FBSimulatorHID *> *)connectToHID;

@end

NS_ASSUME_NONNULL_END
