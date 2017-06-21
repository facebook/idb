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

@class FBSimulator;
@class FBXCTestLogger;
@class FBXCTestConfiguration;
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

/**
 The Context for a Test Run.
 If a Simulator is required, the provided one will be used.

 @param reporter the reporter to report to.
 @param logger the logger to log with.
 @return a new context.
 */
+ (instancetype)contextWithSimulator:(FBSimulator *)simulator reporter:(nullable id<FBXCTestReporter>)reporter logger:(nullable FBXCTestLogger *)logger;

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
 
 @param error an error out for any error that occurs.
 @param configuration the configuration to use.
 @return the Simulator if successful, nil otherwise.
 */
- (nullable FBSimulator *)simulatorForiOSTestRun:(FBXCTestConfiguration *)configuration error:(NSError **)error;

/**
 Causes the Simulator to be released from the test run.

 @param simulator the Simulator to release.
 */
- (void)finishedExecutionOnSimulator:(FBSimulator *)simulator;

@end

NS_ASSUME_NONNULL_END
