/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <FBSimulatorControl/FBSimulatorConfiguration.h>

@class SimDevice;
@class SimDeviceType;
@class SimRuntime;

@protocol FBControlCoreConfiguration_Device;
@protocol FBControlCoreConfiguration_OS;

NS_ASSUME_NONNULL_BEGIN

/**
 Adapting FBSimulatorConfiguration to CoreSimulator.
 */
@interface FBSimulatorConfiguration (CoreSimulator)

#pragma mark Matching Configuration against Available Versions

/**
 Returns a new Simulator Configuration, for the newest available OS for given Device.

 @param device the Device to obtain the OS Configuration for
 @return the newest OS Configuration for the provided Device Configuration, or nil if none is available.
 */
+ (nullable FBOSVersion *)newestAvailableOSForDevice:(FBDeviceType *)device;

/**
 Returns a new Simulator Configuration, for the newest available OS for the current Device.
 This method will Assert if there is no available OS Version for the current Device.

 @return a Configuration with the OS Version Applied.
 */
- (instancetype)newestAvailableOS;

/**
 Returns a new Simulator Configuration, for the oldest available OS for given Device.

 @param device the Device to obtain the OS Configuration for
 @return the newest OS Configuration for the provided Device Configuration, or nil if none is available.
 */
+ (nullable FBOSVersion *)oldestAvailableOSForDevice:(FBDeviceType *)device;

/**
 Returns a new Simulator Configuration, for the oldest available OS for the current Device.
 This method will Assert if there is no available OS Version for the current Device.

 @return a Configuration with the OS Version Applied.
 */
- (instancetype)oldestAvailableOS;

/**
 Creates and returns a FBSimulatorConfiguration object that matches the provided SimDevice.
 Will fail if the Device Type or OS Version are not known by FBiOSTargetConfiguration.

 @param simDevice the SimDevice to infer Simulator Configuration from.
 @param error any error that occurs in the inference of a configuration
 @return A FBSimulatorConfiguration object that matches the device, or nil if the configuration was unknown.
 */
+ (nullable instancetype)inferSimulatorConfigurationFromDevice:(SimDevice *)simDevice error:(NSError **)error;

/**
 Creates and returns a FBSimulatorConfiguration object that matches the provided SimDevice.
 Will synthesize a configuration if the Device Type or OS Version are not known by FBiOSTargetConfiguration.

 @param simDevice the SimDevice to infer a Simulator Configuration from.
 @return A FBSimulatorConfiguration object that matches the device, providing a generic configuration where relevant.
 */
+ (instancetype)inferSimulatorConfigurationFromDeviceSynthesizingMissing:(SimDevice *)simDevice;

/**
 Confirms that the Runtime requirements for the receiver's configurations are met.
 Since it is possible to construct configurations for a wide range of Device Types & Runtimes,
 it may be the case the configuration represents an OS Version or Device that is unavaiable.

 Additionally, there are invalid OS Version to Device Type combinations that need to be checked at runtime.
 This will confirm that the Runtime and Device Typpe are completely compatible and can therefore be created.

 @param error an error out for any error that occurred.
 @return YES if the Runtime requirements are met, NO otherwise.
 */
- (BOOL)checkRuntimeRequirementsReturningError:(NSError **)error;

/**
 Obtains all supported OS Versions.

 @return an Array of OS Versions.
 */
+ (NSArray<FBOSVersion *> *)supportedOSVersions;

/**
 Obtains the supported OS Versions for a Device.
 Will not return OS Versions that cannot be used.

 @param device the device to obtain runtimes for.
 @return an Array of OS Versions the Device can use.
 */
+ (NSArray<FBOSVersion *> *)supportedOSVersionsForDevice:(FBDeviceType *)device;

/**
 Returns an Array of all the Simulator Configurations that are available for the current environment.
 This means each available runtime is combined with each available device.

 @param logger a logger to log missing Devices and OS Versions to.
 @return an array of all possible Simulator Configurations.
 */
+ (NSArray<FBSimulatorConfiguration *> *)allAvailableDefaultConfigurationsWithLogger:(nullable id<FBControlCoreLogger>)logger;

/**
 Returns an Array of all the Simulator Configurations that are available for the current environment.
 This means each available runtime is combined with each available device.

 @param absentOSVersionsOut The OS Version Configurations that are missing.
 @param absentDeviceTypesOut The Simulator Configurations that are missing.
 @return an array of all possible Simulator Configurations.
 */
+ (NSArray<FBSimulatorConfiguration *> *)allAvailableDefaultConfigurationsWithAbsentOSVersionsOut:(NSArray<NSString *> *_Nullable * _Nullable)absentOSVersionsOut absentDeviceTypesOut:(NSArray<NSString *> *_Nullable * _Nullable)absentDeviceTypesOut;

#pragma mark Obtaining CoreSimulator Classes

/**
 Obtains the appropriate SimRuntime for a given configuration, or nil if no matching runtime is available.

 @param error an error out for any error that occurs.
 @return a SimRuntime if one could be obtained, nil otherwise.
 */
- (nullable SimRuntime *)obtainRuntimeWithError:(NSError **)error;

/**
 Obtains the appropriate SimDeviceType for a given configuration, or nil if no matching SimDeviceType is available.

 @param error an error out for any error that occurs.
 @return a SimDeviceType if one could be obtained, nil otherwise.
 */
- (nullable SimDeviceType *)obtainDeviceTypeWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
