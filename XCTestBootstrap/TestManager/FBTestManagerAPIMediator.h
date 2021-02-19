/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class DTXConnection;
@class FBTestManagerContext;

@protocol FBControlCoreLogger;
@protocol FBiOSTarget;
@protocol FBXCTestReporter;

extern const NSInteger FBProtocolVersion;
extern const NSInteger FBProtocolMinimumVersion;

/**
 This is a simplified re-implementation of Apple's _IDETestManagerAPIMediator class.
 This class 'takes over' after an Application Process has been started.
 The class mediates between:
 - The Host
 - The 'testmanagerd' daemon running on iOS.
 - The 'Test Runner', the Appication in which the XCTest bundle is running.
 */
@interface FBTestManagerAPIMediator : NSObject

#pragma mark Public

/**
 Performs the entire process of test execution.
 This incorporates the connection to the 'testmanagerd' daemon, the test bundle and the test execution itself.
 An "error" in the future represents any reason why the test bundle could not be run until completion.
 If the bundle was executed correctly and there are test failures, this does not represent an error.

 @param context the Context of the Test Manager.
 @param target the target.
 @param reporter the (optional) delegate to report test progress too.
 @param logger the (optional) logger to events to.
 @return A future that resolves when test execution has fully completed, or an error occured with the execution.
 */
+ (FBFuture<NSNull *> *)connectAndRunUntilCompletionWithContext:(FBTestManagerContext *)context target:(id<FBiOSTarget>)target reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger;

/**
 Establishes a connection to the testmanagerd service.
 The wrapped DTXConnection is initialized but `resume` must be called on it to be used.

 @param target the target to connect to.
 @param queue the queue to use.
 @param logger the logger to use.
 @return a Future Context wrapping the DTXConnection.
 */
+ (FBFutureContext<DTXConnection *> *)testmanagerdConnectionWithTarget:(id<FBiOSTarget>)target queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
