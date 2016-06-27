/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBDeviceControl/FBDeviceSet.h>

@class DVTDeviceManager;
@class DVTiOSDevice;
@protocol FBControlCoreLogger;

NS_ASSUME_NONNULL_BEGIN

@interface FBDeviceSet ()

@property (nonatomic, strong, readonly) DVTDeviceManager *deviceManager;
@property (nonatomic, nullable, strong, readonly) id<FBControlCoreLogger> logger;

- (nullable DVTiOSDevice *)dvtDeviceWithUDID:(NSString *)udid;

@end

NS_ASSUME_NONNULL_END
