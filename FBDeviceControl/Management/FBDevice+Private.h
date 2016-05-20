/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBDeviceControl/FBDevice.h>

@class DVTAbstractiOSDevice;
@class FBAMDevice;
@protocol FBDeviceOperator;

@interface FBDevice ()

@property (nonatomic, strong, readonly) DVTAbstractiOSDevice *dvtDevice;
@property (nonatomic, strong, readonly) FBAMDevice *amDevice;

- (instancetype)initWithDeviceOperator:(id<FBDeviceOperator>)operator dvtDevice:(DVTAbstractiOSDevice *)dvtDevice amDevce:(FBAMDevice *)amDevice;

@end
