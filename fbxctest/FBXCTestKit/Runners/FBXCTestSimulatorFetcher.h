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
@class FBSimulatorControl;
@class FBTestRunConfiguration;

NS_ASSUME_NONNULL_BEGIN

/**
 Fetches a Simulator for a Test.
 */
@interface FBXCTestSimulatorFetcher : NSObject

/**
 Creates a Simulator Fetcher for the given configuration

 @param configuration the configuration to use.
 @param error an error out for any error that occurs.
 @return a Fetcher for the given Configuration.
 */
+ (nullable instancetype)withConfiguration:(FBTestRunConfiguration *)configuration error:(NSError **)error;

/**
 Gets a Simulator capable of running a logic test.
 This means a Simulator will be used, but not booted.

 @param error an error out for any error that occurs.
 @return a Simulator if successful, nil otherwise.
 */
- (nullable FBSimulator *)fetchSimulatorForLogicTestWithError:(NSError **)error;

/**
 Gets a Simulator capable of running a logic test.
 This means a Simulator will be used, which is also booted.

 @param error an error out for any error that occurs.
 @return a Simulator if successful, nil otherwise.
 */
- (nullable FBSimulator *)fetchSimulatorForApplicationTestsWithError:(NSError **)error;

/**
 Return the Simulator after the Test Run is completed.

 @param simulator the Simulator to dispose of.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)returnSimulator:(FBSimulator *)simulator error:(NSError **)error;

/**
 The FBSimulatorControl Instance.
 */
@property (nonatomic, strong, readonly) FBSimulatorControl *simulatorControl;

@end

NS_ASSUME_NONNULL_END
