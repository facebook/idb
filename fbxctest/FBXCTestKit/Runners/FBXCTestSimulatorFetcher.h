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
@class FBXCTestConfiguration;
@protocol FBControlCoreLogger;

/**
 Fetches a Simulator for a Test.
 */
@interface FBXCTestSimulatorFetcher : NSObject

/**
 Creates a Simulator Fetcher for the given configuration

 @param workingDirectory the working directory.
 @param logger the logger to use.
 @param error an error out for any error that occurs.
 @return a Fetcher for the given Configuration.
 */
+ (nullable instancetype)fetcherWithWorkingDirectory:(NSString *)workingDirectory logger:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error;

/**
 Gets a Simulator for the configuration provided in the constructor.

 @param configuration the configuration to fetch for.
 @param error an error out for any error that occurs.
 @return a Simulator if successful, nil otherwise.
 */
- (nullable FBSimulator *)fetchSimulatorForConfiguration:(FBXCTestConfiguration *)configuration error:(NSError **)error;

/**
 Return the Simulator after the Test Run is completed.

 @param simulator the Simulator to dispose of.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)returnSimulator:(FBSimulator *)simulator error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
