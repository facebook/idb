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

@protocol FBTestManagerMediatorDelegate;
@protocol FBControlCoreLogger;

/**
 This is massively simplified reimplementations of Apple's _IDETestManagerAPIMediator class,
 which is mediator (running on host) between test runner (app that executes XCTest bundle on device) and testmanagerd (running on device), that helps to launch tests.
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
@property (nonatomic, weak) id<FBTestManagerMediatorDelegate> delegate;

/**
 Logger object to log events to, may be nil.
 */
@property (nonatomic, strong) id<FBControlCoreLogger> logger;

/**
 Creates and returns a mediator with given paramenters

 @param device a device that on which test runner is running
 @param testRunnerPID a process id of test runner (XCTest bundle)
 @param sessionIdentifier a session identifier of test that should be started
 @return Prepared FBTestRunnerConfiguration
 */
+ (instancetype)mediatorWithDevice:(DVTAbstractiOSDevice *)device testRunnerPID:(pid_t)testRunnerPID sessionIdentifier:(NSUUID *)sessionIdentifier;

/**
 Starts test and establishes connection between test runner(XCTest bundle) and testmanagerd

 @param error If there is an error, upon return contains an NSError object that describes the problem.
 @return YES if connection request has started successfuly, NO otherwise
 */
- (BOOL)connectTestRunnerWithTestManagerDaemonWithError:(NSError **)error;

/**
 Terminates connection between test runner(XCTest bundle) and testmanagerd
 */
- (void)disconnectTestRunnerAndTestManagerDaemon;

@end


@protocol FBTestManagerMediatorDelegate <NSObject>

/**
 Request to launch an application

 @param mediator a mediator requesting launch
 @param path a path for application to launch
 @param bundleID a bundleID for application to launch
 @param arguments arguments that application should be launched with
 @param environmentVariables environment variables that application should be launched with
 @param error error for error handling
 @return YES if the request was successful, otherwise NO.
 */
- (BOOL)testManagerMediator:(FBTestManagerAPIMediator *)mediator
      launchProcessWithPath:(NSString *)path
                   bundleID:(NSString *)bundleID
                  arguments:(NSArray *)arguments
       environmentVariables:(NSDictionary *)environmentVariables
                      error:(NSError **)error;

@end
