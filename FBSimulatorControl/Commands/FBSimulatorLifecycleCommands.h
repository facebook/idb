/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBProcessInfo;
@class FBSimulator;
@class FBSimulatorBootConfiguration;

/**
 Interactions for the Lifecycle of the Simulator.
 */
@protocol FBSimulatorLifecycleCommands <NSObject>

/**
 Boots the Simulator with the default Simulator Launch Configuration.\
 Will fail if the Simulator is currently booted.

 @return the reciever, for chaining.
 */
- (BOOL)bootSimulatorWithError:(NSError **)error;

/**
 Boots the Simulator with the default Simulator Launch Configuration.
 Will fail if the Simulator is currently booted.

 @return the reciever, for chaining.
 */
- (BOOL)bootSimulator:(FBSimulatorBootConfiguration *)configuration error:(NSError **)error;

/**
 Shuts the Simulator down.
 Will fail if the Simulator is not booted.

 @return the reciever, for chaining.
 */
- (BOOL)shutdownSimulatorWithError:(NSError **)error;

/**
 Opens the provided URL on the Simulator.

 @param url the URL to open.
 @return the reciever, for chaining.
 */
- (BOOL)openURL:(NSURL *)url error:(NSError **)error;

/**
 Terminates a Subprocess of the Simulator.

 @param process the process to terminate.
 @return the reciever, for chaining.
 */
- (BOOL)terminateSubprocess:(FBProcessInfo *)process error:(NSError **)error;

@end

/**
 The Implementation of FBSimulatorLifecycleCommands
 */
@interface FBSimulatorLifecycleCommands : NSObject <FBSimulatorLifecycleCommands>

/**
 The Designated Intializer

 @param simulator the Simulator.
 @return a new Simulator Lifecycle Commands Instance.
 */
+ (instancetype)commandsWithSimulator:(FBSimulator *)simulator;

@end

NS_ASSUME_NONNULL_END
