/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Options that apply to each FBSimulatorControl instance.
 */
typedef NS_OPTIONS(NSUInteger, FBSimulatorManagementOptions){
  FBSimulatorManagementOptionsDeleteAllOnFirstStart = 1 << 0, /** Deletes all of the devices in the pool, upon creation of the Pool */
  FBSimulatorManagementOptionsKillAllOnFirstStart = 1 << 1, /** Kills all of the devices in the pool, upon creation of the Pool */
  FBSimulatorManagementOptionsKillSpuriousSimulatorsOnFirstStart = 1 << 2, /** Kills all Simulators not managed by FBSimulatorControl when creating a Pool */
  FBSimulatorManagementOptionsIgnoreSpuriousKillFail = 1 << 3, /** Don't fail Pool creation when failing to kill spurious Simulators */
  FBSimulatorManagementOptionsKillSpuriousCoreSimulatorServices = 1 << 4, /** Kills CoreSimulatorService daemons from the non-current Xcode version when creating a Pool */
};

/**
 A Value object with the information required to create a Simulator Pool.
 */
@interface FBSimulatorControlConfiguration : NSObject <NSCopying, FBJSONSerializable, FBDebugDescribeable>

/**
 Creates and returns a new Configuration with the provided parameters.

 @param options the options for Simulator Management.
 @param deviceSetPath the Path to the Device Set. If nil, the default Device Set will be used.
 @return a new Configuration Object with the arguments applied.
 */
+ (instancetype)configurationWithDeviceSetPath:(nullable NSString *)deviceSetPath options:(FBSimulatorManagementOptions)options logger:(nullable id<FBControlCoreLogger>)logger reporter:(nullable id<FBEventReporter>)reporter;

/**
 The Location of the SimDeviceSet. If no path is provided, the default device set will be used.
 */
@property (nonatomic, copy, nullable, readonly) NSString *deviceSetPath;

/**
 The Options for Simulator Management.
 */
@property (nonatomic, assign, readonly) FBSimulatorManagementOptions options;

/**
 The Logger to use for logging.
 */
@property (nonatomic, strong, nullable, readonly) id<FBControlCoreLogger> logger;

/**
 The Event Reporter to use for reporting events.
 */
@property (nonatomic, strong, nullable, readonly) id<FBEventReporter> reporter;

@end

/**
 Global CoreSimulatorConfiguration
 */
@interface FBSimulatorControlConfiguration (Helpers)

/**
 The Location of the Default SimDeviceSet
 */
+ (NSString *)defaultDeviceSetPath;

@end

NS_ASSUME_NONNULL_END
