/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulatorConfiguration+Private.h>
#import <FBSimulatorControl/FBSimulatorLaunchConfiguration.h>

@protocol FBSimulatorLaunchConfiguration_Scale <NSObject>

- (NSString *)scaleString;

@end

@interface FBSimulatorLaunchConfiguration_Scale_25 : FBSimulatorConfigurationVariant_Base <FBSimulatorLaunchConfiguration_Scale>
@end

@interface FBSimulatorLaunchConfiguration_Scale_50 : FBSimulatorConfigurationVariant_Base <FBSimulatorLaunchConfiguration_Scale>
@end

@interface FBSimulatorLaunchConfiguration_Scale_75 : FBSimulatorConfigurationVariant_Base <FBSimulatorLaunchConfiguration_Scale>
@end

@interface FBSimulatorLaunchConfiguration_Scale_100 : FBSimulatorConfigurationVariant_Base <FBSimulatorLaunchConfiguration_Scale>
@end

@interface FBSimulatorLaunchConfiguration ()

@property (nonatomic, strong, readonly) id<FBSimulatorLaunchConfiguration_Scale> scale;

- (instancetype)withScale:(id<FBSimulatorLaunchConfiguration_Scale>)scale;

@end
