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
#import <FBSimulatorControl/FBSimulatorEventSink.h>
#import <FBSimulatorControl/FBSimulatorHistory.h>

@class FBProcessLaunchConfiguration;
@class FBSimulatorBinary;
@class FBSimulatorSession;

/**
 An Object responsible for building `FBSimulatorHistory` be converting events into state.
 Links are maintained to previous states, so the entire history of the Simulator can be interrogated at any time.
 */
@interface FBSimulatorHistoryGenerator : NSObject <FBSimulatorEventSink>

/**
 Creates and returns a State Event Sink for the given Simulator
 */
+ (instancetype)withSimulator:(FBSimulator *)simulator;

/**
 The Current History.
 */
@property (nonatomic, strong, readonly) FBSimulatorHistory *history;

@end
