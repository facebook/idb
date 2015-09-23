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
@class FBSimulatorConfiguration;
@class FBSimulatorControlConfiguration;
@class FBSimulatorPool;
@class FBManagedSimulator;
@class SimDevice;
@class SimDeviceSet;

@protocol FBSimulatorLogger;

/**
 A wrapper around the DeviceSet, to support meaningful queries.
 */
@interface FBSimulatorPool : NSObject

/**
 Creates and returns an FBSimulatorPool with the provided deviceSet.

 @param configuration the configuration to use.
 @param deviceSet the SimDeviceSet to Manage.
 @returns a new FBSimulatorPool.
 */
+ (instancetype)poolWithConfiguration:(FBSimulatorControlConfiguration *)configuration deviceSet:(SimDeviceSet *)deviceSet;

/**
 Returns the configuration for the reciever.
 */
@property (nonatomic, copy, readonly) FBSimulatorControlConfiguration *configuration;

/**
 An Ordered Set of the Simulators for the DeviceSet.
 This includes allocated and un-allocated simulators, as well as managed and unmanaged simulators.
 Ordering is based on name descending.
 Is an NSOrderedSet<FBSimulator>
 */
@property (nonatomic, copy, readonly) NSOrderedSet *allSimulators;

/**
 Returns a device matching the UDID, if one exists.
 */
- (FBSimulator *)simulatorWithUDID:(NSString *)udidString;

/**
 Returns a Device for the given parameters. Will create devices where necessary.
 If you plan on running multiple tests in the lifecycle of a process, you should use `freeDevice:error:`
 otherwise devices will continue to be allocated.

 @param configuration the Configuration of the Device to Allocate. Must not be nil.
 @param error an error out for any error that occured.
 @returns a device if one could be found or created, nil if an error occured.
 */
- (FBManagedSimulator *)allocateSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration error:(NSError **)error;

/**
 Marks a device that was previously returned from `allocateDeviceWithName:sdkVersion:error:` as free.
 Call this when multiple test runs, or simulators are to be re-used in a process.

 @param device the Device to Free.
 @param error an error out for any error that occured.
 @returns YES if the freeing of the device was successful, NO otherwise.
 */
- (BOOL)freeSimulator:(FBManagedSimulator *)simulator error:(NSError **)error;

/**
 Kills all of the Simulators that this Pool is responsible for.

 @param error an error out if any error occured.
 @returns an array of the Simulators that this were killed if successful, nil otherwise.
 */
- (NSArray *)killManagedSimulatorsWithError:(NSError **)error;

/**
 Kills all of the Simulators that this, or any other Pool is responsible for.

 @param error an error out if any error occured.
 @returns an array of the Simulators that this were killed if successful, nil otherwise.
 */
- (NSArray *)killPooledSimulatorsWithError:(NSError **)error;

/**
 Kills all of the Simulators that this are not managed by this pool, or any other.

 @param error an error out if any error occured.
 @returns an array of the Simulators that this were killed if successful, nil otherwise.
 */
- (NSArray *)killUnmanagedSimulatorsWithError:(NSError **)error;

/**
 Erases the Simulators that this Pool is responsible for.
 Kills them first to ensure they are in a steady state.

 @param error an error out if any error occured.
 @returns an array of the Simulators that this Pool is responsible if successful, nil otherwise.
 */
- (NSArray *)eraseManagedSimulatorsWithError:(NSError **)error;

/**
 Delete all of the Simulators Managed by this Pool, killing them first.

 @param error an error out if any error occured.
 @returns an Array of the names of the Simulators that were deleted if successful, nil otherwise.
 */
- (NSArray *)deleteManagedSimulatorsWithError:(NSError **)error;

/**
 Delete all of the Simulators that this Pool, or any other pool is responsiblef for, killing them first.

 @param error an error out if any error occured.
 @returns an Array of the names of the Simulators that were deleted if successful, nil otherwise.
 */
- (NSArray *)deletePooledSimulatorsWithError:(NSError **)error;

@end

/**
 Fetchers for Specific and Groups of Simulators
 */
@interface FBSimulatorPool (Fetchers)

/**
 Finds the Device UDID for the given device name and SDK version combination.
 If a simulatorSDK is not provided, the first device matching the given deviceName will be returned.
 This will search for all devices in the set, whether the Pool will manage them or not.

 @param deviceName the Device Name to search for. Must not be nil.
 @param simulatorSDK the SDK Runtime of the Simulator. May be nil.
 @returns The Device UDID that matches the parameters, nil if no match could be found.
 */
- (NSString *)deviceUDIDWithName:(NSString *)deviceName simulatorSDK:(NSString *)simulatorSDK;

/**
 Returns the first Simulator allocated by FBSimulatorPool, based on the device type alone.

 @param deviceType the Device Type of the Device to search for. Must not be nil.
 @return The Allocated device created by FBSimulatorPool.
 */
- (FBManagedSimulator *)allocatedSimulatorWithDeviceType:(NSString *)deviceType;

/**
 An Ordered Set of the Simulators that this Pool is responsible for.
 This includes allocated and un-allocated simulators.
 Ordering is based on name descending.
 Is an NSOrderedSet<FBManagedSimulator>
 */
@property (nonatomic, copy, readonly) NSOrderedSet *allSimulatorsInPool;

/**
 An Ordered Set of the Simulators that any posible Pool is responsible for.
 This includes allocated and un-allocated simulators.
 Ordering is based on name descending.
 Is an NSOrderedSet<FBManagedSimulator>
 */
@property (nonatomic, copy, readonly) NSOrderedSet *allPooledSimulators;

/**
 An Ordered Set of the Simulators that this Pool has allocated.
 This includes only allocated simulators.
 Is an NSOrderedSet<FBManagedSimulator>
 */
@property (nonatomic, copy, readonly) NSOrderedSet *allocatedSimulators;

/**
 An Ordered Set of the Simulators that this Pool has allocated.
 This includes only allocated simulators.
 Ordering is based on name descending.
 Is an NSOrderedSet<FBManagedSimulator>
 */
@property (nonatomic, copy, readonly) NSOrderedSet *unallocatedSimulators;

/**
 An Ordered Set of all the Simulators for the Device Set.
 Is an NSOrderedSet<FBSimulator>
 */
@property (nonatomic, copy, readonly) NSOrderedSet *allSimulators;

/**
 An Ordered Set of the Simulators that no Pool is responsible for.
 Is an NSOrderedSet<FBSimulator>
 */
@property (nonatomic, copy, readonly) NSOrderedSet *unmanagedSimulators;

/**
 An Ordered Set of the Simulators that have been launched by any pool, or not by FBSimulatorControl at all.
 Is an NSOrderedSet<FBSimulator>
 */
@property (nonatomic, copy, readonly) NSOrderedSet *launchedSimulators;

@end

/**
 Helpers to Debug what is going on with the state of the world, useful after-the-fact (CI)
 */
@interface FBSimulatorPool (Debug)

/**
 A Description of the Pool, with extended debug information
 */
- (NSString *)debugDescription;

/**
 Log SimDeviceSet interactions.
 */
- (void)startLoggingSimDeviceSetInteractions:(id<FBSimulatorLogger>)logger;

@end
