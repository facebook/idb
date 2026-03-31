/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class FBBundleDescriptor;
@class FBSimulatorConfiguration;
@class FBSimulatorControlConfiguration;
@class FBSimulatorServiceContext;
@class FBSimulatorSet;
@protocol FBControlCoreLogger;

/**
 The Root Class for the FBSimulatorControl Framework.
 */
@interface FBSimulatorControl : NSObject

#pragma mark Initializers

/**
 Creates and returns a new `FBSimulatorControl` instance.

 @param configuration the Configuration to setup the instance with.
 @param error any error that occurred during instantiation.
 @return a new FBSimulatorControl instance.
 */
+ (nullable instancetype)withConfiguration:(nonnull FBSimulatorControlConfiguration *)configuration error:(NSError * _Nullable * _Nullable)error;

#pragma mark Properties

/**
 The Set of Simulators managed by FBSimulatorControl.
 */
@property (nonnull, nonatomic, readonly, strong) FBSimulatorSet *set;

/**
 The Service Context.
 */
@property (nonnull, nonatomic, readonly, strong) FBSimulatorServiceContext *serviceContext;

/**
 The Configuration that FBSimulatorControl was instantiated with.
 */
@property (nonnull, nonatomic, readwrite, copy) FBSimulatorControlConfiguration *configuration;

@end
