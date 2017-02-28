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
@class FBApplicationLaunchConfiguration;
@class FBTestBundle;
@class FBTestLaunchConfiguration;
@protocol FBTestManagerTestReporter;

NS_ASSUME_NONNULL_BEGIN

/**
 Commands to perform on a Simulator, related to XCTest.
 */
@protocol FBSimulatorXCTestCommands <NSObject>

/**
 Starts testing application using test bundle. It will use simulator's auxillaryDirectory as working directory

 @param testLaunchConfiguration configuration used to launch test.
 @return the reciever, for chaining.
 */
- (BOOL)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration error:(NSError **)error;

/**
 Starts testing application using test bundle.

 @param testLaunchConfiguration configuration used to launch test.
 @param reporter the reporter to report to.
 @return the reciever, for chaining.
 */
- (BOOL)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(nullable id<FBTestManagerTestReporter>)reporter error:(NSError **)error;

/**
 Starts testing application using test bundle.

 @param testLaunchConfiguration configuration used to launch test.
 @param reporter the reporter to report to.
 @param workingDirectory xctest working directory.
 @return the reciever, for chaining.
 */
- (BOOL)startTestWithLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration reporter:(nullable id<FBTestManagerTestReporter>)reporter workingDirectory:(nullable NSString *)workingDirectory error:(NSError **)error;

/**
 Starting test runner does not wait till test execution has finished. In same maner as starting application does not wait till application has finished execution.
 This method can be used in order to wait till all testing sessions have finished and possbily process the results.

 @param timeout the maximum time to wait for test to finish.
 @return the reciever, for chaining.
 */
- (BOOL)waitUntilAllTestRunnersHaveFinishedTestingWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

@end

/**
 The implementation of the FBSimulatorXCTestCommands instance.
 */
@interface FBSimulatorXCTestCommands : NSObject <FBSimulatorXCTestCommands>

/**
 The Designated Initializer.

 @param simulator the simulator to run against.
 @return a new Simulator XCTest Commands Instance.
 */
+ (instancetype)commandsWithSimulator:(FBSimulator *)simulator;

@end

NS_ASSUME_NONNULL_END
