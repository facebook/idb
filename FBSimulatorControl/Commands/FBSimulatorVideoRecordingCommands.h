/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBSimulator;
@class FBSimulatorVideoStream;

/**
 An implementation of Video Recording Commands for Simulators.
 */
@interface FBSimulatorVideoRecordingCommands : NSObject <FBVideoRecordingCommands, FBVideoStreamCommands>

@end
