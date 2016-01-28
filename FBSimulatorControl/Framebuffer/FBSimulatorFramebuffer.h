/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBJSONSerializationDescribeable.h>

@class FBSimulator;
@class FBSimulatorLaunchConfiguration;
@class SimDeviceFramebufferService;
@protocol FBFramebufferDelegate;

/**
 A container and client for a Simulator's Framebuffer that forwards important events to delegates.

 The class itself doesn't perform much behaviour other than to manage the lifecycle.
 Implementors of FBFramebufferDelegate perform individual behaviours such as recording videos and images.
 */
@interface FBSimulatorFramebuffer : NSObject <FBJSONSerializationDescribeable>

/**
 Creates and returns a new FBSimulatorDirectLaunch object for the provided SimDeviceFramebufferService.

 @param framebufferService the SimDeviceFramebufferService to connect to.
 @param launchConfiguration the launch configuration to create the service for.
 @param simulator the Simulator to which the Framebuffer belongs.
 @return a new FBSimulatorDirectLaunch instance. Must not be nil.
 */
+ (instancetype)withFramebufferService:(SimDeviceFramebufferService *)framebufferService configuration:(FBSimulatorLaunchConfiguration *)launchConfiguration simulator:(FBSimulator *)simulator;

/**
 Starts listening for Framebuffer events on a background queue.
 Events are delivered to the Event Sink on this same background queue.
 */
- (void)startListeningInBackground;

/**
 Stops listening for Framebuffer envents on the background queue.
 Events are delivered to the Event Sink on this same background queue.
 */
- (void)stopListening;

@end
