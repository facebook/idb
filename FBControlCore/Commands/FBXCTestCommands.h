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

@class FBTestLaunchConfiguration;

/**
 Commands to perform on an iOS Target, related to XCTest.
 */
@protocol FBXCTestCommands <NSObject>

/**
 Bootstraps a test run using a Test Launch Configuration. 
 It will use the iOS Targets's auxillaryDirectory as a working directory.

 @param testLaunchConfiguration the configuration used for the test launch.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration error:(NSError **)error;

/**
 Calling -[FBXCTestCommands startTestWithLaunchConfiguration:error:] will start the execution of the test run.
 This does not mean that the test execution will have finished.
 This method can be used in order to wait for the testing execution to finish and process the results.

 @param timeout the maximum time to wait for test execution to finish.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)waitUntilAllTestRunnersHaveFinishedTestingWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
