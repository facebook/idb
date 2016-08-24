/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBTestManagerContext;

@protocol FBTestManagerProcessInteractionDelegate;
@protocol FBTestManagerTestReporter;
@protocol FBControlCoreLogger;
@protocol FBDeviceOperator;

extern const NSInteger FBProtocolVersion;
extern const NSInteger FBProtocolMinimumVersion;

NS_ASSUME_NONNULL_BEGIN

/**
 This is a simplified re-implementation of Apple's _IDETestManagerAPIMediator class.
 This class 'takes over' after an Application Process has been started.
 The class mediates between:
 - The Host
 - The 'testmanagerd' daemon running on iOS.
 - The 'Test Runner', the Appication in which the XCTest bundle is running.
 */
@interface FBTestManagerAPIMediator : NSObject

/**
 Delegate object used to handle application install & launch request
 */
@property (nonatomic, weak, readonly) id<FBTestManagerProcessInteractionDelegate> processDelegate;

/**
 Logger object to log events to, may be nil.
 */
@property (nonatomic, nullable, strong, readonly) id<FBControlCoreLogger> logger;

/**
 Creates and returns a mediator with given paramenters

 @param context the Context of the Test Manager.
 @param deviceOperator a device operator for device that test runner is running on
 @param processDelegate the Delegate to handle application interactivity.
 @param reporter the (optional) delegate to report test progress too.
 @param logger the (optional) logger to events to.
 @return Prepared FBTestRunnerConfiguration
 */
+ (instancetype)mediatorWithContext:(FBTestManagerContext *)context deviceOperator:(id<FBDeviceOperator>)deviceOperator processDelegate:(id<FBTestManagerProcessInteractionDelegate>)processDelegate reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger;

/**
 Establishes a connection between the host, testmanagerd and the Test Bundle.
 This connection is established synchronously, until a timeout occurs.

 @param timeout a maximum time to wait for the connection to be established.
 @param error If there is an error, upon return contains an NSError object that describes the problem.
 @return YES if connection has been established successfuly, NO otherwise.
 */
- (BOOL)connectTestRunnerWithTestManagerDaemonWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

/**
 Executes the Test Plan over the established connection.
 This should be called after `-[FBTestManagerAPIMediator connectTestRunnerWithTestManagerDaemonWithTimeout:error:]`
 has successfully completed.
 Events will be delivered to the reporter asynchronously.

 @param timeout a maximum time to wait for the connection to be established.
 @param error If there is an error, upon return contains an NSError object that describes the problem.
 @return YES if the Test Plan execution has started succesfully, NO otherwise.
 */
- (BOOL)executeTestPlanWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

/**
 Terminates connection between test runner(XCTest bundle) and testmanagerd
 */
- (void)disconnectTestRunnerAndTestManagerDaemon;

/**
 Connecting mediator does not wait till test execution has finished.
 This method can be used in order to wait till test execution has finished.

 @param timeout the the maximum time to wait for test to finish.
 @return YES if the test execution has finished, NO otherwise.
 */
- (BOOL)waitUntilTestRunnerAndTestManagerDaemonHaveFinishedExecutionWithTimeout:(NSTimeInterval)timeout;

@end

NS_ASSUME_NONNULL_END
