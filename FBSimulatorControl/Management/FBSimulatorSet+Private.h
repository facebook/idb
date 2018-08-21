/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulatorSet.h>

@class FBSimulatorContainerApplicationLifecycleStrategy;
@class FBSimulatorInflationStrategy;
@class FBSimulatorNotificationUpdateStrategy;

@interface FBSimulatorSet ()

- (instancetype)initWithConfiguration:(FBSimulatorControlConfiguration *)configuration deviceSet:(SimDeviceSet *)deviceSet logger:(id<FBControlCoreLogger>)logger delegate:(id<FBiOSTargetSetDelegate>)delegate;

@property (nonatomic, strong, readonly) dispatch_queue_t workQueue;
@property (nonatomic, strong, readonly) FBSimulatorInflationStrategy *inflationStrategy;
@property (nonatomic, strong, readonly) FBSimulatorContainerApplicationLifecycleStrategy *containerApplicationStrategy;
@property (nonatomic, strong, readonly) FBSimulatorNotificationUpdateStrategy *notificationUpdateStrategy;

@end
