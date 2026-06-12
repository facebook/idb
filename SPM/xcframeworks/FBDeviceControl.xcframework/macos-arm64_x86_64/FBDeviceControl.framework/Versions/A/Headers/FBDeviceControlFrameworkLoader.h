/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <FBDeviceControl/FBAMDefines.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBControlCoreLogger;

/**
 Loads Frameworks that FBDeviceControl depends on and initializes values.
 */
@interface FBDeviceControlFrameworkLoader : FBControlCoreFrameworkLoader

/**
 The AMDevice Calls to use.
 */
@property (nonatomic, assign, class, readonly) AMDCalls amDeviceCalls;

@end

NS_ASSUME_NONNULL_END
