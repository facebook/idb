/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <FBSimulatorControl/FBSimulatorControl.h>

NS_ASSUME_NONNULL_BEGIN

@class FBFuture;
@class FBSimulator;
@class FBSimulatorControlConfiguration;

@interface FBSimulatorsManager : NSObject

- (instancetype)initWithSimulatorControlConfiguration:(FBSimulatorControlConfiguration *)configuration;

- (FBFuture<FBSimulator *> *)createSimulatorWithName:(nullable NSString *)name withOSName:(nullable NSString *)osName;

@end

NS_ASSUME_NONNULL_END
