/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBSimulatorApplication;

/**
 The default prefix for Pool-Managed Simulators
 */
extern NSString *const FBSimulatorControlConfigurationDefaultNamePrefix;

typedef NS_OPTIONS(NSUInteger, FBSimulatorManagementOptions){
  FBSimulatorManagementOptionsDeleteAllOnFirstStart = 1 << 0,
  FBSimulatorManagementOptionsKillSpuriousSimulatorsOnFirstStart = 1 << 1,
  FBSimulatorManagementOptionsIgnoreSpuriousKillFail = 1 << 2,
  FBSimulatorManagementOptionsAlwaysCreateWhenAllocating = 1 << 3,
  FBSimulatorManagementOptionsDeleteOnFree = 1 << 4,
  FBSimulatorManagementOptionsEraseOnFree = 1 << 5,
};

/**
 A Value object with the information required to create a Simulator Pool.
 */
@interface FBSimulatorControlConfiguration : NSObject<NSCopying>

/**
 Creates and returns a new Configuration with the provided parameters.

 @param simulatorApplication the FBSimulatorApplication for the Simulator.app.
 @param options the options for Simulator Management.
 @returns a new Configuration Object with the arguments applied.
 */
+ (instancetype)configurationWithSimulatorApplication:(FBSimulatorApplication *)simulatorApplication
                                        deviceSetPath:(NSString *)deviceSetPath
                                              options:(FBSimulatorManagementOptions)options;

/**
 The FBSimulatorApplication for the Simulator.app.
 */
@property (nonatomic, copy, readonly) FBSimulatorApplication *simulatorApplication;

/**
 The Location of the SimDeviceSet. If no path is provided, the default device set will be used.
 */
@property (nonatomic, copy, readonly) NSString *deviceSetPath;

/**
 The options for Simulator Management.
 */
@property (nonatomic, assign, readonly) FBSimulatorManagementOptions options;

@end
