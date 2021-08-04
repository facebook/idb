/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBSimulatorControlConfiguration;
@class SimDevice;

NS_ASSUME_NONNULL_BEGIN

/**
 A class for obtaining information about Simulators that FBSimulatorControl cares about.
 */
@interface FBSimulatorProcessFetcher : NSObject

/**
 Creates and Returns a Process Fetcher.

 @param processFetcher the Process Fetcher to use.
 @return a new Simulator Process Fetcher.
 */
+ (instancetype)fetcherWithProcessFetcher:(FBProcessFetcher *)processFetcher;

/**
 The Underlying Process Fetcher.
 */
@property (nonatomic, strong, readonly) FBProcessFetcher *processFetcher;

#pragma mark CoreSimulatorService

/**
 Fetches an NSArray<FBProcessInfo *> of all com.apple.CoreSimulator.CoreSimulatorService.

 @return an Array of all the CoreSimulatorService Processes.
 */
- (NSArray<FBProcessInfo *> *)coreSimulatorServiceProcesses;

#pragma mark - Predicates

/**
 Constructs a Predicate that matches CoreSimulatorService Processes for the current xcode versions.

 @return an NSPredicate that operates on an Collection of FBProcessInfo *.
 */
+ (NSPredicate *)coreSimulatorProcessesForCurrentXcode;

@end

NS_ASSUME_NONNULL_END
