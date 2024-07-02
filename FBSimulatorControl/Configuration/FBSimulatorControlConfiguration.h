/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A Value object with the information required to create a Simulator Pool.
 */
@interface FBSimulatorControlConfiguration : NSObject <NSCopying>

/**
 Creates and returns a new Configuration with the provided parameters.

 @param deviceSetPath the Path to the Device Set. If nil, the default Device Set will be used.
 @param logger the logger to use.
 @param reporter the reporter to report to.
 @return a new Configuration Object with the arguments applied.
 */
+ (instancetype)configurationWithDeviceSetPath:(nullable NSString *)deviceSetPath logger:(nullable id<FBControlCoreLogger>)logger reporter:(nullable id<FBEventReporter>)reporter;

/**
 The Location of the SimDeviceSet. If no path is provided, the default device set will be used.
 */
@property (nonatomic, copy, nullable, readonly) NSString *deviceSetPath;

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
