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

@protocol FBFileDataConsumer;

/**
 A Process wrapper for running Logic Tests.
 */
@interface FBLogicTestProcess : NSObject

/**
 The Designated Initializer.

 @param launchPath the Launch Path of the executable
 @param arguments the Arguments to the executable.
 @param environment the Environment Variables to set.
 @param stdOutReader the Reader of the Stdout.
 @param stdErrReader the Reader of the Stderr.
 @param xctestProcessIsSubprocess YES if the xctest process is a subprocess of the launched process, NO if the process launched is xctest
 @return a new Logic Test Process
 */
+ (instancetype)processWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment stdOutReader:(id<FBFileDataConsumer>)stdOutReader stdErrReader:(id<FBFileDataConsumer>)stdErrReader xctestProcessIsSubprocess:(BOOL)xctestProcessIsSubprocess;

/**
 Starts the Process.

 @param error an error out for any error that occurs.
 @return the PID of the launched process, -1 on error.
 */
- (pid_t)startWithError:(NSError **)error;

/**
 Terminates the process.
 */
- (void)terminate;

/**
 Waits to the process to complete.

 @param timeout the timeout in seconds to wait for the process to terminate.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)waitForCompletionWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
