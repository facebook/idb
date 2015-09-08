/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBSimulatorApplication;
@class FBSimulatorConfiguration;
@class FBSimulatorControlConfiguration;
@class FBSimulatorPool;
@class FBSimulatorSession;

extern NSString *const FBSimulatorControlErrorDomain;

/**
 An Abstraction over the mechanics of creating, launching and cleaning-up Simulators.
 Currently only manages one Simulator.
 */
@interface FBSimulatorControl : NSObject

/**
 Returns the Singleton `FBSimulatorControl` instance. Takes a Mandatory bucket id in setup.

 @param configuration the Configuration to setup the instance with.
 @returns a shared instance with the first configuration.
 */
+ (instancetype)sharedInstanceWithConfiguration:(FBSimulatorControlConfiguration *)configuration;

/**
 Creates and returns a new FBSimulatorSession instance. Does not launch the Simulator or any Applications.

 @param configuration the Configuration of the Simulator to Launch.
 @param error an outparam for describing any error that occured during the creation of the Session.
 @returns A new `FBSimulatorSession` instance, or nil if an error occured.
 */
- (FBSimulatorSession *)createSessionForSimulatorConfiguration:(FBSimulatorConfiguration *)simulatorConfiguration error:(NSError **)error;

/**
 Starts the `FBSimulatorApplication` on any available device matching the `deviceName` and `sdkVersion`.

 @param application the `FBSimulatorApplication` to launch. Must not be nil.
 @param arguments the launch arguments to pass to the application. Must not be nil.
 @param simulatorConfiguration the Configuration of the Simulator to Launch.
 @param error an outparam for describing any error that occured during the creation and launch of the Application on the Simulator. Must not be nil.
 @returns A new `FBSimulatorSession` instance, or nil if an error occured.
 */
- (FBSimulatorSession *)startApplication:(FBSimulatorApplication *)application withArguments:(NSArray *)arguments simulatorConfiguration:(FBSimulatorConfiguration *)simulatorConfiguration error:(NSError **)error;

@property (nonatomic, readonly) FBSimulatorPool *simulatorPool;

@end
