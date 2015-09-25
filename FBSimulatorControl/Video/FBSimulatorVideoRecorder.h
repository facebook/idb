/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBTerminationHandle.h>
#import <FBSimulatorControl/FBSimulatorLogger.h>

@class FBSimulator;

/**
 A Class that Records Video for a given Simulator.

 Helpful reference from:
 - Apple Technical QA1740
 - https://github.com/square/zapp/ZappVideoController.m
 - https://github.com/appium/screen_recording
 */
@interface FBSimulatorVideoRecorder : NSObject <FBTerminationHandle>

/**
 Create a new FBSimulatorVideoRecorder for the provided Simulator.
 
 @param simulator the Simulator to Record.
 @param logger a logger to record interactions. May be nil.
 @return a new Video Recorder instance.
 */
+ (instancetype)forSimulator:(FBSimulator *)simulator logger:(id<FBSimulatorLogger>)logger;

/**
 Starts recording the Simulator to a File.
 Will delete and overwrite any existing video for the given filePath.
 
 @param filePath the File to Record into.
 @param error the error out, for any error that occurred.
 @returns YES if the recording started successfully, NO otherwise.
 */
- (BOOL)startRecordingToFilePath:(NSString *)filePath error:(NSError **)error;

/**
 Ends recording of the Simulator.
 
 @param error the error out, for any error that occured.
 @return the Path of the recorded movie if successful, NO otherwise.
 */
- (NSString *)stopRecordingWithError:(NSError **)error;

@end
