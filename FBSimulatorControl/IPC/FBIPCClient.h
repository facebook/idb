/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBSimulator;
@class FBSimulatorSet;

/**
 The client for IPC.
 */
@interface FBIPCClient : NSObject

/**
 The Set that the IPC Client should send Remote Events for
 */
@property (nonatomic, strong, readonly) FBSimulatorSet *set;

/**
 Creates and retuns an IPC Client for the provided Simulator Set.
 
 @param set the Simulator Set to use.
 */
+ (instancetype)withSimulatorSet:(FBSimulatorSet *)set;

/**
 Notifies the FBSimulatorControl process that owns the Simulator's Framebuffer to start recording video.
 
 @param simulator the Simulator to start recording video for.
 */
- (void)startRecordingVideo:(FBSimulator *)simulator;

/**
 Notifies the FBSimulatorControl process that owns the Simulator's Framebuffer to stop recording video.

 @param simulator the Simulator to stop recording video for.
 */
- (void)stopRecordingVideo:(FBSimulator *)simulator;

@end
