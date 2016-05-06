/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class DVTAbstractiOSDevice;

@protocol FBTestManagerProcessInteractionDelegate;
@protocol FBTestManagerTestReporter;
@protocol FBControlCoreLogger;

/**
 This is a simplified re-implementation of Apple's _IDETestManagerAPIMediator class.
 The class mediates between:
 - The Host
 - The 'testmanagerd' daemon running on iOS.
 - The 'Test Runner', the Appication in which the XCTest bundle is running.
 */
@interface FBTestManagerAPIMediator : NSObject

/**
 XCTest session identifier
 */
@property (nonatomic, copy, readonly) NSUUID *sessionIdentifier;

/**
 Process id of test runner application
 */
@property (nonatomic, assign, readonly) pid_t testRunnerPID;

/**
 Delegate object used to handle application install & launch request
 */
@property (nonatomic, weak, readwrite) id<FBTestManagerProcessInteractionDelegate> processDelegate;

/**
 Delegate to which test activity is reported.
 */
@property (nonatomic, weak, readwrite) id<FBTestManagerTestReporter> reporter;

/**
 Logger object to log events to, may be nil.
 */
@property (nonatomic, strong, readwrite) id<FBControlCoreLogger> logger;

/**
 Creates and returns a mediator with given paramenters

 @param device a device that on which test runner is running
 @param testRunnerPID a process id of test runner (XCTest bundle)
 @param sessionIdentifier a session identifier of test that should be started
 @return Prepared FBTestRunnerConfiguration
 */
+ (instancetype)mediatorWithDevice:(DVTAbstractiOSDevice *)device testRunnerPID:(pid_t)testRunnerPID sessionIdentifier:(NSUUID *)sessionIdentifier;

/**
 Starts test and establishes connection between test runner(XCTest bundle) and testmanagerd, synchronously.

 @param error If there is an error, upon return contains an NSError object that describes the problem.
 @return YES if connection connection has been established successfuly, NO otherwise.
 */
- (BOOL)connectTestRunnerWithTestManagerDaemonWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

/**
 Terminates connection between test runner(XCTest bundle) and testmanagerd
 */
- (void)disconnectTestRunnerAndTestManagerDaemon;

@end
