/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBTestLaunchConfiguration.h>
#import <FBControlCore/FBTerminationHandle.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBTestManagerTestReporter;

/**
 The Termination Handle Type.
 */
extern FBTerminationHandleType const FBTerminationHandleTypeTestOperation;

/**
 A Running Test Operation that can awaited and cancelled.
 */
@protocol FBXCTestOperation <NSObject, FBTerminationAwaitable>

@end

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
 @param reporter a reporter for optionally reporting to.
 @return a Test Operation if successful, nil otherwise.
 */
- (nullable id<FBXCTestOperation>)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(nullable id<FBTestManagerTestReporter>)reporter error:(NSError **)error;

/**
 Calling -[FBXCTestCommands startTestWithLaunchConfiguration:error:] will start the execution of the test run.
 This does not mean that the test execution will have finished.
 This method can be used in order to wait for the testing execution to finish and process the results.

 @param timeout the maximum time to wait for test execution to finish.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)waitUntilAllTestRunnersHaveFinishedTestingWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

/**
 Lists the testables for a provided test bundle.

 @param bundlePath the bundle path of the test bundle
 @param error an error out for any error that occurs.
 @return an array of strings for the test names if successful, NO otherwise.
 */
- (nullable NSArray<NSString *> *)listTestsForBundleAtPath:(NSString *)bundlePath timeout:(NSTimeInterval)timeout error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
