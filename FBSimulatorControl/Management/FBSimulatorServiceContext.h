/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class FBSimulatorControlConfiguration;
@class SimDeviceSet;
@class SimDeviceType;
@class SimRuntime;
@class SimServiceContext;

@protocol FBControlCoreLogger;

/**
 An FBSimulatorControl wrapper for SimServiceContext.
 */
@interface FBSimulatorServiceContext : NSObject

#pragma mark Initializers

/**
 Returns the shared Service Context instance.

 @param logger the logger to use.
 @return the shared context.
 */
+ (nonnull instancetype)sharedServiceContextWithLogger:(nullable id<FBControlCoreLogger>)logger;

/**
 Returns the shared Service Context instance.

 @return the shared context.
 */
+ (nonnull instancetype)sharedServiceContext;

#pragma mark Public Methods

/**
 Return the paths to all of the device sets.
 */
- (nonnull NSArray<NSString *> *)pathsOfAllDeviceSets;

/**
 Returns all of the supported runtimes.
 */
- (nonnull NSArray<SimRuntime *> *)supportedRuntimes;

/**
 Returns all of the supported device types.
 */
- (nonnull NSArray<SimDeviceType *> *)supportedDeviceTypes;

/**
 Obtains the SimDeviceSet for a given configuration.

 @param configuration the configuration to use.
 @param error an error out for any error that occurs.
 @return the Device Set if present. nil otherwise.
 */
- (nullable SimDeviceSet *)createDeviceSetWithConfiguration:(nonnull FBSimulatorControlConfiguration *)configuration error:(NSError * _Nullable * _Nullable)error;

@end
