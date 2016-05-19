/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <IDEFoundation/_IDETestManagerAPIMediator.h>

@protocol FBTestManagerProcessInteractionDelegate;
@protocol FBControlCoreLogger;

/**
 This is hacked _IDETestManagerAPIMediator that can work without few dependent objects.
 making it easier to disassemble it and reimplement FBTestManagerAPIMediator
 */
@interface FBAugmentedTestManagerAPIMediator : _IDETestManagerAPIMediator

@property (nonatomic, weak) id<FBTestManagerProcessInteractionDelegate> delegate;

/**
 Creates and returns a mediator with the provided parameters.

 @param device a device that on which test runner is running
 @param testRunnerPID a process id of test runner (XCTest bundle)
 @param sessionIdentifier a session identifier of test that should be started
 @param logger the Logger to log to.
 @return a API Mediator.
 */
+ (instancetype)mediatorWithDevice:(DVTDevice *)device testRunnerPID:(pid_t)testRunnerPID sessionIdentifier:(NSUUID *)sessionIdentifier logger:(id<FBControlCoreLogger>)logger;

/**
 Starts test and establishes connection between test runner(XCTest bundle) and testmanagerd
 */
- (void)connectTestRunnerWithTestManagerDaemon;

@end
