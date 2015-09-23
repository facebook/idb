/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulatorConfiguration.h>

@class SimDeviceType;
@class SimRuntime;

/**
 Adapting FBSimulatorConfiguration to CoreSimulator.
 */
@interface FBSimulatorConfiguration (CoreSimulator)

/**
 The SimRuntime for the current configuration.
 Will return nil, if the runtime is unavailable
 */
@property (nonatomic, strong, readonly) SimRuntime *runtime;

/**
 The SimRuntime for the current configuration.
 Will return nil, if the runtime is unavailable
 */
@property (nonatomic, strong, readonly) SimDeviceType *deviceType;

/**
 The Defaults override for the Device-Specific scale key in NSUserDefaults.
 See 'defaults read com.apple.iphonesimulator'
 */
@property (nonatomic, copy, readonly) NSString *lastScaleKey;

/**
 The Command Line switch to override the Device-Specific scale of a directly-launched the Simulator.
 See 'defaults read com.apple.iphonesimulator'
 */
@property (nonatomic, copy, readonly) NSString *lastScaleCommandLineSwitch;

/**
 Returns a new Configuration, for the specific SimRuntime.
 */
- (instancetype)withRuntime:(SimRuntime *)runtime;

/**
 Returns a new Configuration, for the specific DeviceType.
 */
- (instancetype)withDeviceType:(SimDeviceType *)deviceType;

/**
 Returns an NSDictionary<FBSimulatorConfiguration, SimRuntime> for the available runtimes.
 */
+ (NSDictionary *)configurationsToAvailableRuntimes;

/**
 Returns an NSDictionary<FBSimulatorConfiguration, SimDeviceType> for the available devices.
 */
+ (NSDictionary *)configurationsToAvailableDeviceTypes;

@end
