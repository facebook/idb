/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;
@class FBXCTestCommandLine;
@class FBXCTestLogger;
@protocol FBXCTestReporter;

/**
 Context for the Test Run.
 Separate from configuration as these properties are not serializable.
 */
@interface FBXCTestContext : NSObject

#pragma mark Initializers

/**
 The Context for a Test Run.
 If a Simulator is required, it will be created or fetched.

 @param reporter the reporter to report to.
 @param logger the logger to log with.
 @return a new context.
 */
+ (instancetype)contextWithReporter:(nullable id<FBXCTestReporter>)reporter logger:(nullable FBXCTestLogger *)logger;

#pragma mark Properties

/**
 The Logger to log to.
 */
@property (nonatomic, strong, readonly, nullable) FBXCTestLogger *logger;

/**
 The Reporter to report to.
 */
@property (nonatomic, strong, readonly, nullable) id<FBXCTestReporter> reporter;

#pragma mark Public Methods

/**
 Obtains the Simulator for an iOS Test Run.

 @param commmandLine the configuration to use.
 @return A future that wraps the Simulator;.
 */
- (FBFuture<FBSimulator *> *)simulatorForCommandLine:(FBXCTestCommandLine *)commmandLine;

/**
 Causes the Simulator to be released from the test run.

 @param simulator the Simulator to release.
 @return a future that resolves when the simulator has been freed.
 */
- (FBFuture<NSNull *> *)finishedExecutionOnSimulator:(FBSimulator *)simulator;

@end

NS_ASSUME_NONNULL_END
