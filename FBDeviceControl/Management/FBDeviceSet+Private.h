/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <FBDeviceControl/FBDeviceSet.h>

@protocol FBControlCoreLogger;

NS_ASSUME_NONNULL_BEGIN

@interface FBDeviceSet ()

@property (nonatomic, nullable, strong, readonly) id<FBControlCoreLogger> logger;

@end

NS_ASSUME_NONNULL_END
