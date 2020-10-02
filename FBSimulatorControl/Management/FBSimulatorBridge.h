/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBApplicationLaunchConfiguration;
@class FBSimulator;

/**
 Wraps the 'SimulatorBridge' Connection and Protocol
 */
@interface FBSimulatorBridge : NSObject <FBJSONSerializable>

#pragma mark Initializers

/**
 Creates and Returns a SimulatorBridge for the attaching to the provided Simulator.
 The future will fail if the connection could not established.

 @param simulator the Simulator to attach to.
 @return a FBSimulatorBridge wrapped in a Future.
 */
+ (FBFuture<FBSimulatorBridge *> *)bridgeForSimulator:(FBSimulator *)simulator;

/**
 Should be called when the connection to the remote bridge should be disconnected.
 */
- (void)disconnect;

#pragma mark Interacting with the Simulator

/**
 Sets latitude and longitude of the Simulator.
 The behaviour of a directly-launched Simulator differs from Simulator.app slightly, in that the location isn't automatically set.
 Simulator.app will typically set a location from NSUserDefaults, so Applications will have a default location.

 @param latitude the latitude of the location.
 @param longitude the longitude of the location.
 @return a Future that resolves when the location has been sent.
 */
- (FBFuture<NSNull *> *)setLocationWithLatitude:(double)latitude longitude:(double)longitude;

/**
 Enables Accessibility on the Simulator.

 @return a future that resolves when accessibility has been enabled.
 */
- (FBFuture<NSNull *> *)enableAccessibility;

/**
 The Acessibility Elements.
 Obtain the acessibility elements for the main screen.
 The returned value is fully JSON serializable.

 @return the accessibility elements for the main screen, wrapped in a Future.
 */
- (FBFuture<NSArray<NSDictionary<NSString *, id> *> *> *)accessibilityElements;

/**
 Obtain the acessibility element for the main screen at the given point.
 The returned value is fully JSON serializable.

 @param point the coordinate at which to obtain the accessibility element.
 @return the accessibility element at the provided point, wrapped in a Future.
 */
- (FBFuture<NSDictionary<NSString *, id> *> *)accessibilityElementAtPoint:(CGPoint)point;

/**
 Enables or disables the hardware keyboard.

 @param enabled YES if enabled, NO if disabled.
 @return a Future that resolves when successful.
 */
- (FBFuture<NSNull *> *)setHardwareKeyboardEnabled:(BOOL)enabled;

@end

NS_ASSUME_NONNULL_END
