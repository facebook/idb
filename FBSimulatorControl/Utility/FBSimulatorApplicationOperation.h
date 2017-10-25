/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;
@class FBProcessInfo;
@class FBApplicationLaunchConfiguration;

/**
 An Operation for an Application.
 */
@interface FBSimulatorApplicationOperation : NSObject

/**
 The Designated Initializer.

 @param configuration the configuration launched with.
 @param launchFuture a future that resolves when the Application has finished launching.
 @return a new Application Operation.
 */
+ (FBFuture<FBSimulatorApplicationOperation *> *)operationWithSimulator:(FBSimulator *)simulator configuration:(FBApplicationLaunchConfiguration *)configuration launchFuture:(FBFuture<NSNumber *> *)launchFuture;

/**
 The Configuration Launched with.
 */
@property (nonatomic, copy, readonly) FBApplicationLaunchConfiguration *configuration;

/**
 The Launched Process Info.
 */
@property (nonatomic, copy, readonly) FBProcessInfo *process;

@end

NS_ASSUME_NONNULL_END
