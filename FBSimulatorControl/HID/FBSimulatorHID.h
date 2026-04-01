/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <FBSimulatorControl/FBSimulatorIndigoHID.h>
#import <FBSimulatorControl/FBSimulatorPurpleHID.h>

@class FBSimulator;

NS_ASSUME_NONNULL_BEGIN

/**
 The HID abstraction layer for a Simulator, providing two transport paths:

 1. Indigo (IndigoHIDRegistrationPort) — for touch, button, and keyboard events.
    Payloads are constructed by FBSimulatorIndigoHID and sent via SimDeviceLegacyHIDClient.
    Guest-side: SimHIDVirtualServiceManager dispatches on eventKind + target.

 2. PurpleWorkspacePort — for GSEvent-based events (e.g., device orientation changes).
    Payloads are constructed by FBSimulatorPurpleHID and sent via raw mach_msg_send.
    Guest-side: GraphicsServices._PurpleEventCallback → backboardd.

 See Indigo.h and GSEvent.h for wire format documentation.
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

/**
 Sends a raw mach message to the simulator's PurpleWorkspacePort.
 Used for GSEvent-based HID events (e.g., orientation changes) that bypass
 the Indigo HID system. The data must contain a complete mach message
 including mach_msg_header_t. The msgh_remote_port field will be patched
 with the PurpleWorkspacePort looked up from the simulator's bootstrap namespace.

 This is synchronous — callers are responsible for dispatching to the appropriate
 queue and wrapping in a future if needed (mirrors sendIndigoMessageData:completionQueue:completion:).

 @param data the complete mach message to send.
 @param error an error out for any error that occurs.
 @return YES if the message was sent successfully, NO otherwise.
 */
- (BOOL)sendPurpleEvent:(NSData *)data error:(NSError **)error;

#pragma mark Properties

/**
 The Queue on which messages are sent to the HID Server.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

/**
 The Indigo payload builder (touch, button, keyboard).
 */
@property (nonatomic, strong, readonly) FBSimulatorIndigoHID *indigo;

/**
 The Purple/GSEvent payload builder (orientation, shake).
 */
@property (nonatomic, strong, readonly) FBSimulatorPurpleHID *purple;

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
