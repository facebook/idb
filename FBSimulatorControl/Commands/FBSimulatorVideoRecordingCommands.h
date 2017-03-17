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

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;
@class FBSimulatorBitmapStream;

/**
 Simulator-Specific Application Commands.
 */
@protocol FBSimulatorStreamingCommands

/**
 Creates a Bitmap Stream for a Simulator.

 @param error an error out for any error that occurs.
 @return the Video Recording session on success, nil otherwise.
 */
- (nullable FBSimulatorBitmapStream *)createStreamWithError:(NSError **)error;

@end

/**
 An implementation of Video Recording Commands for Simulators.
 */
@interface FBSimulatorVideoRecordingCommands : NSObject <FBVideoRecordingCommands, FBSimulatorStreamingCommands>

/**
 Creates a FBSimulatorApplicationCommands instance.

 @param simulator the Simulator to perform actions on.
 @return a new FBSimulatorApplicationCommands instance.
 */
+ (instancetype)commandsWithSimulator:(FBSimulator *)simulator;

@end

NS_ASSUME_NONNULL_END
