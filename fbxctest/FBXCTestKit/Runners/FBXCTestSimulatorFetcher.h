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
@protocol FBControlCoreLogger;

/**
 Fetches a Simulator for a Test.
 */
@interface FBXCTestSimulatorFetcher : NSObject

#pragma mark Initializers

/**
 Creates a Simulator Fetcher for the given configuration

 @param workingDirectory the working directory.
 @param logger the logger to use.
 @param error an error out for any error that occurs.
 @return a Fetcher for the given Configuration.
 */
+ (nullable instancetype)fetcherWithWorkingDirectory:(NSString *)workingDirectory logger:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error;

#pragma mark Public Methods

/**
 Gets a Simulator for the configuration provided in the constructor.

 @param commandLine the configuration to fetch for.
 @return a Future that resolves with the Simulator if successful, nil otherwise.
 */
- (FBFuture<FBSimulator *> *)fetchSimulatorForCommandLine:(FBXCTestCommandLine *)commandLine;

/**
 Return the Simulator after the Test Run is completed.

 @param simulator the Simulator to dispose of.
 @return a Future that resolves when successful
 */
- (FBFuture<NSNull *> *)returnSimulator:(FBSimulator *)simulator;

@end

NS_ASSUME_NONNULL_END
