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
  FBSimulatorManagementOptionsDeleteManagedSimulatorsOnFirstStart = 1 << 0,
  FBSimulatorManagementOptionsKillUnmanagedSimulatorsOnFirstStart = 1 << 1,
  FBSimulatorManagementOptionsDeleteOnFree = 1 << 2,
  FBSimulatorManagementOptionsEraseOnFree = 1 << 3,
};

/**
 A Value object with the information required to create a Simulator Pool.
 */
@interface FBSimulatorControlConfiguration : NSObject<NSCopying>

/**
 Creates and returns a new Configuration with the provided parameters.

 @param simulatorApplication the FBSimulatorApplication for the Simulator.app.
 @param namePrefix the String to prefix all `FBSimulatorControl` managed Simulators with. Will default to 'E2E' if nil.
 @param bucketID the Bucket of the launched Simulators. Multiple processes cannot share the same Bucket ID.
 @param options the options for Simulator Management.
 @returns a new Configuration Object with the arguments applied.
 */
+ (instancetype)configurationWithSimulatorApplication:(FBSimulatorApplication *)simulatorApplication
                                        deviceSetPath:(NSString *)deviceSetPath
                                           namePrefix:(NSString *)namePrefix
                                               bucket:(NSInteger)bucketID
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
 The String to prefix all `FBSimulatorControl` Simulators with.
 Simulators in the same Pool will share the same `namePrefix` and `bucketID`.
 */
@property (nonatomic, copy, readonly) NSString *namePrefix;

/**
 The Bucket of the launched Simulators. Multiple processes cannot share the same Bucket ID.
 */
@property (nonatomic, assign, readonly) NSInteger bucketID;

/**
 The options for Simulator Management.
 */
@property (nonatomic, assign, readonly) FBSimulatorManagementOptions options;

@end
