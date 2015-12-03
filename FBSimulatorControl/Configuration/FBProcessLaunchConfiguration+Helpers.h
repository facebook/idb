/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBProcessLaunchConfiguration.h>

@class FBSimulator;

@interface FBProcessLaunchConfiguration (Helpers)

/**
 Adds Environment to the Launch Configuration

 @param environmentAdditions the Environment to Add. Must be an NSDictionary<NSString *, NSString*>>
 */
- (instancetype)withEnvironmentAdditions:(NSDictionary *)environmentAdditions;

/**
 Adds Diagnostic Environment information to the reciever's environment configuration.

 @return a new Process Launch Configuration with the diagnostic environment applied.
 */
- (instancetype)withDiagnosticEnvironment;

/**
 Uses DYLD_INSERT_LIBRARIES to inject a dylib into the launched application's process.

 @param filePath the File Path to the Dynamic Library. Must not be nil.
 */
- (instancetype)injectingLibrary:(NSString *)filePath;

/**
 Injects the Shimulator Dylib into the launched process;
 */
- (instancetype)injectingShimulator;

/**
 Creates the file handles for the reciever.
 
 @param stdOut an out param for the stdout file handle.
 @param stdErr an out param for the stderr file handle.
 @param error an out param for any error that occurred.
 @return YES if successful, NO otherwise.
 */
- (BOOL)createFileHandlesWithStdOut:(NSFileHandle **)stdOut stdErr:(NSFileHandle **)stdErr error:(NSError **)error;

/**
 Creates the Dictionary of launch options for launching an Agent.

 @param stdOut the stdout to use, may be nil.
 @param stdErr the stderr to use, may be nil.
 @param error an out param for any error that occurred.
 @return a Dictionary if successful, nil otherwise.
 */
- (NSDictionary *)agentLaunchOptionsWithStdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr error:(NSError **)error;

@end
