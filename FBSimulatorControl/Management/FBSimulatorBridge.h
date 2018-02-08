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
#import <FBSimulatorControl/FBSimulatorBridgeCommands.h>

NS_ASSUME_NONNULL_BEGIN

@class FBApplicationLaunchConfiguration;
@class FBSimulator;

/**
 Wraps the 'SimulatorBridge' Connection and Protocol
 */
@interface FBSimulatorBridge : NSObject <FBJSONSerializable, FBSimulatorBridgeCommands>

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
 The Acessibility Elements.
 Obtain the acessibility element for the main screen at the given point.
 The returned value is fully JSON serializable.

 @return the accessibility elements for the main screen, wrapped in a Future.
 */
- (FBFuture<NSArray<NSDictionary<NSString *, id> *> *> *)accessibilityElements;

/**
 Launches an Application.

 @param configuration the Configuration of the App to Launch,
 @param stdOutPath the Path of a File to write stdout to.
 @param stdErrPath the path of a File to write stderr to.
 @return the Process Identifier of the Launched Application if successful wrapped in a Future.
 */
- (FBFuture<NSNumber *> *)launch:(FBApplicationLaunchConfiguration *)configuration stdOutPath:(nullable NSString *)stdOutPath stdErrPath:(nullable NSString *)stdErrPath;

@end

NS_ASSUME_NONNULL_END
