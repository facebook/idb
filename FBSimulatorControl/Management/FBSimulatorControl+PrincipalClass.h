/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBSimulatorPool.h>

@class FBApplicationBundle;
@class FBSimulatorConfiguration;
@class FBSimulatorControlConfiguration;
@class FBSimulatorPool;
@class FBSimulatorServiceContext;
@class FBSimulatorSet;
@protocol FBControlCoreLogger;

NS_ASSUME_NONNULL_BEGIN

/**
 The Root Class for the FBSimulatorControl Framework.
 */
@interface FBSimulatorControl : NSObject

#pragma mark Initializers

/**
 Creates and returns a new `FBSimulatorControl` instance.

 @param configuration the Configuration to setup the instance with.
 @param logger the logger to use to verbosely describe what is going on. May be nil.
 @param error any error that occurred during instantiation.
 @return a new FBSimulatorControl instance.
 */
+ (nullable instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger error:(NSError **)error;

/**
 Creates and returns a new `FBSimulatorControl` instance.

 @param configuration the Configuration to setup the instance with.
 @param error any error that occurred during instantiation.
 @return a new FBSimulatorControl instance.
 */
+ (nullable instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration error:(NSError **)error;

#pragma mark Properties

/**
 The Set of Simulators managed by FBSimulatorControl.
 */
@property (nonatomic, strong, readonly) FBSimulatorSet *set;

/**
 The Pool adds conveniences to the management of the Simulator Set.
 */
@property (nonatomic, strong, readonly) FBSimulatorPool *pool;

/**
 The Service Context.
 */
@property (nonatomic, strong, readonly) FBSimulatorServiceContext *serviceContext;

/**
 The Configuration that FBSimulatorControl was instantiated with.
 */
@property (nonatomic, copy, readwrite) FBSimulatorControlConfiguration *configuration;

@end

NS_ASSUME_NONNULL_END
