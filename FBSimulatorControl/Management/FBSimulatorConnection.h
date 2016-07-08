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

@class FBFramebuffer;
@class FBSimulator;
@class FBSimulatorBridge;
@class FBSimulatorHID;
@class FBSimulatorLaunchConfiguration;
@protocol FBSimulatorEventSink;
@class FBApplicationLaunchConfiguration;

NS_ASSUME_NONNULL_BEGIN

/**
 A Simulator Connection is a container for all of the relevant services that can be obtained when launching via: -[SimDevice bootWithOptions:error].
 Typically these are all the services with which Simulator.app can interact with, except that we have them inside FBSimulatorControl.
 */
@interface FBSimulatorConnection : NSObject  <FBJSONSerializable>

#pragma mark Initializers

/**
 The Designated Initializer

 @param framebuffer the Framebuffer. May be nil.
 @param hid the Indigo HID Port. May be nil.
 @param bridge the underlying bridge. Must not be nil.
 @param eventSink the event sink. Must not be nil.
 */
- (instancetype)initWithFramebuffer:(nullable FBFramebuffer *)framebuffer hid:(nullable FBSimulatorHID *)hid bridge:(FBSimulatorBridge *)bridge eventSink:(id<FBSimulatorEventSink>)eventSink;

/**
 Tears down the bridge and it's resources, waiting for any asynchronous teardown to occur before returning.
 Must only ever be called from the main thread.

 @param timeout the number of seconds to wait for termination to occur in. If 0 or fewer, the reciever won't wait.
 @return YES if the termination occurred within timeout seconds, NO otherwise.
 */
- (BOOL)terminateWithTimeout:(NSTimeInterval)timeout;

#pragma mark Properties

/**
 The FBSimulatorFramebuffer Instance.
 */
@property (nonatomic, strong, readonly, nullable) FBFramebuffer *framebuffer;

/**
 The FBSimulatorFramebuffer Instance.
 */
@property (nonatomic, strong, readonly, nullable) FBSimulatorHID *hid;

/**
 The FBSimulatorFramebuffer Instance.
 */
@property (nonatomic, strong, readonly) FBSimulatorBridge *bridge;

@end

NS_ASSUME_NONNULL_END
