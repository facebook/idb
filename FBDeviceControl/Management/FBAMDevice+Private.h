/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBDeviceControl/FBAMDevice.h>

NS_ASSUME_NONNULL_BEGIN

@interface FBAMDevice ()

@property (nonatomic, assign, readonly) CFTypeRef amDevice;

@property (nonatomic, nullable, copy, readwrite) NSString *name;
@property (nonatomic, nullable, copy, readwrite) NSString *deviceName;

@end

NS_ASSUME_NONNULL_END
