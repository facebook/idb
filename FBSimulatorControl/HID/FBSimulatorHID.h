/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <FBSimulatorControl/FBSimulatorIndigoHID.h>

@class FBSimulator;

NS_ASSUME_NONNULL_BEGIN

/**
 A Wrapper around the mach_port_t that is created in the booting of a Simulator.
 The IndigoHIDRegistrationPort is essential for backboard, otherwise UI events aren't synthesized properly.
 */
@interface FBSimulatorHID : NSObject

#pragma mark Initializers

/**
 Creates and returns a FBSimulatorHID Instance for the provided Simulator.
 Will fail if a HID Port could not be registered for the provided Simulator.
 Registration may need to occur prior to booting.

 @param simulator the Simulator to create a IndigoHIDRegistrationPort for.
 @return a FBSimulatorHID if successful, nil otherwise.
 */
+ (FBFuture<FBSimulatorHID *> *)hidForSimulator:(FBSimulator *)simulator;

#pragma mark Lifecycle

/**
 Obtains the Reply Port for the Simulator.
 This must be obtained in order to send IndigoHID events to the Simulator.
 This should be obtained after the Simulator is booted.

 @return A future that resolves when connected.
 */
- (FBFuture<NSNull *> *)connect;

/**
 Disconnects from the remote HID.
 
 @return A future that resolves when disconnected
 */
- (FBFuture<NSNull *> *)disconnect;

#pragma mark HID Manipulation

/**
 Sends the event payload

 @param data the payload data
 @return A future that resolves when the event has been sent.
 */
- (FBFuture<NSNull *> *)sendEvent:(NSData *)data;

/**
 Sends the event payload, synchronously.
 This should only be used when the caller can guarantee that all calls to this API are performed from the same queue.
 
 @param data the payload data
 @param completionQueue the queue to call back on
 @param completion the completion block to invoke
 */
- (void)sendIndigoMessageData:(NSData *)data completionQueue:(dispatch_queue_t)completionQueue completion:(void (^)(NSError * _Nullable))completion;

#pragma mark Properties

/**
 The Queue on which messages are sent to the HID Server.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

/**
 The Indigo event translator.
 */
@property (nonatomic, strong, readonly) FBSimulatorIndigoHID *indigo;

/**
 The dimensions of the main screen.
 */
@property (nonatomic, assign, readonly) CGSize mainScreenSize;

/**
 The scale of the main screen.
 */
@property (nonatomic, assign, readonly) float mainScreenScale;

@end

NS_ASSUME_NONNULL_END
