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
 An Environment Variable that is inserted into Simulator.app processes launched by FBSimulatorControl.
 This makes the process of determining launched Simulator.app processes far simpler
 as otherwise it is difficult to determine the UDID corresponding to a Simulator.app based on information
 available to external processes.
 */
extern NSString *const FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID;

/**
 An Environment Variable that is inserted into Simulator.app processes launched by FBSimulatorControl.
 This makes the process of determining launched Simulator.app processes far simpler
 as otherwise it is difficult to determine the UDID corresponding to a Simulator.app based on information
 available to external processes.
 */
extern NSString *const FBSimulatorControlSimulatorLaunchEnvironmentDeviceSetPath;

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

#pragma mark The Container 'Simulator.app'

/**
 Fetches an NSArray<FBProcessInfo *> of all Simulator Application Processes.

 @return an Array of all the Simulator.app Processes for the current version of Xcode.
 */
- (NSArray<FBProcessInfo *> *)simulatorApplicationProcesses;

/**
 Fetches a Dictionary, mapping Simulator UDID to Simulator.app Process.
 This can be used to obtain an understanding of the Simulator.app processes are for a number of Simulators.

 @param udids an array of the udids to look for.
 @param unclaimedOut an outparam for optionally returning Simulator.app processes that are not associated with any particular UDID.
 @return a Dictionary mapping UDIDs to Simulator.app processes.
 */
- (NSDictionary<NSString *, FBProcessInfo *> *)simulatorApplicationProcessesByUDIDs:(NSArray<NSString *> *)udids unclaimed:(NSArray<FBProcessInfo *> *_Nullable * _Nullable)unclaimedOut;

/**
 Fetches a Dictionary, mapping Device Set Path to Simulator Application Process.
 If no Device Set Path defined, NSNull will be the key.

 @return a Dictionary, mapping a String Device Set Path to UDID. NSNull if a Simulator.app does not have an identifiable Device Set Path.
 */
- (NSDictionary<id, FBProcessInfo *> *)simulatorApplicationProcessesByDeviceSetPath;

/**
 Fetches the Process Info for a given Simulator.

 @param simDevice the Simulator to fetch Process Info for.
 @return Application Process Info if any could be obtained, nil otherwise.
 */
- (nullable FBProcessInfo *)simulatorApplicationProcessForSimDevice:(SimDevice *)simDevice;

/**
 Fetches the Process Info for a given Simulator, with a timeout as the process info may take a while to appear

 @param simDevice the Simulator to fetch Process Info for.
 @param timeout the time to wait for the process info to appear.
 @return Application Process Info if any could be obtained, nil otherwise.
 */
- (nullable FBProcessInfo *)simulatorApplicationProcessForSimDevice:(SimDevice *)simDevice timeout:(NSTimeInterval)timeout;

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
 Returns a Predicate that matches simulator processes only from the Xcode version in the provided configuration.

 @param configuration the configuration to match against.
 @return an NSPredicate that operates on an Collection of FBProcessInfo *.
 */
+ (NSPredicate *)simulatorsProcessesLaunchedUnderConfiguration:(FBSimulatorControlConfiguration *)configuration;

/**
 Returns a Predicate that matches simulator processes launched by FBSimulatorControl

 @return an NSPredicate that operates on an Collection of FBProcessInfo *.
 */
+ (NSPredicate *)simulatorApplicationProcessesLaunchedBySimulatorControl;

/**
 Constructs a Predicate that matches CoreSimulatorService Processes for the current xcode versions.

 @return an NSPredicate that operates on an Collection of FBProcessInfo *.
 */
+ (NSPredicate *)coreSimulatorProcessesForCurrentXcode;

@end

NS_ASSUME_NONNULL_END
