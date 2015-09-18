/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBSimulator.h>
#import <FBSimulatorControl/FBSimulatorSessionState.h>

@class FBProcessLaunchConfiguration;
@class FBSimulatorBinary;
@class FBSimulatorSession;

/**
 An object responsible for creating `FBSimulatorSessionState` objects.
 Maintains the links to the previous state, so previous state can be queried.
 */
@interface FBSimulatorSessionStateGenerator : NSObject

/**
 Creates and returns a new Generator for the given session
 */
+ (instancetype)generatorWithSession:(FBSimulatorSession *)session;

/**
 Updates the lifecycle of the session with the given enumeration
 */
- (instancetype)updateLifecycle:(FBSimulatorSessionLifecycleState)lifecycle;

/**
 Updates the Simulator State.
 */
- (instancetype)updateSimulatorState:(FBSimulatorState)state;

/**
 Creates Process State for the given launch config.
 */
- (instancetype)update:(FBProcessLaunchConfiguration *)launchConfig withProcessIdentifier:(NSInteger)processIdentifier;

/**
 Updates the diagnostic information about for a given launched process.
 */
- (instancetype)update:(FBSimulatorApplication *)application withDiagnosticNamed:(NSString *)diagnosticName data:(id)data;

/**
 Removes the Process State for the given binary.
 */
- (instancetype)remove:(FBSimulatorBinary *)binary;

/**
 Returns the current Session State
 */
- (FBSimulatorSessionState *)currentState;

@end
