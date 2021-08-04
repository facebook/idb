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

#pragma mark The Simulator's launchd_sim

/**
 Fetches an NSArray<FBProcessInfo *> of all launchd_sim processes.

 @return an Array of launchd_sim processes.
 */
- (NSArray<FBProcessInfo *> *)launchdProcesses;

/**
 Fetches the Process Info for a given Simulator's launchd_sim.

 @param simDevice the Simulator to fetch Process Info for.
 @return Process Info if any could be obtained, nil otherwise.
 */
- (nullable FBProcessInfo *)launchdProcessForSimDevice:(SimDevice *)simDevice;

/**
 Fetches a Dictionary, mapping Simulator UDID to launchd_sim process.

 @param udids an Array of all the UDIDs to obtain launchd_sim processes for.
 @return a Dictionary, mapping UDIDs to launchd_sim processes.
 */
- (NSDictionary<NSString *, FBProcessInfo *> *)launchdProcessesByUDIDs:(NSArray<NSString *> *)udids;

/**
 Fetches a Dictionary, mapping launchd_sim to the device set that contains it.

 @return Dictionary, mapping launchd_sim to the device set that contains it.
 */
- (NSDictionary<FBProcessInfo *, NSString *> *)launchdProcessesToContainingDeviceSet;

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
