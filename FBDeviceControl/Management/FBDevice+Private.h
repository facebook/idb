/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBDeviceControl/FBDevice.h>

@class DVTiOSDevice;
@class FBAMDevice;
@protocol FBDeviceOperator;

@interface FBDevice ()

@property (nonatomic, strong, readonly) DVTiOSDevice *dvtDevice;
@property (nonatomic, strong, readonly) FBAMDevice *amDevice;

- (instancetype)initWithSet:(FBDeviceSet *)set amDevice:(FBAMDevice *)device logger:(id<FBControlCoreLogger>)logger;

@end
