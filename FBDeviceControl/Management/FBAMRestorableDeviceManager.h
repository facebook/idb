/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBDeviceControl/FBDeviceManager.h>
#import <FBDeviceControl/FBAMDefines.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAMRestorableDevice;

/**
 Class for obtaining FBAMRestorableDevice instances.
 */
@interface FBAMRestorableDeviceManager : FBDeviceManager<FBAMRestorableDevice *>

@end

NS_ASSUME_NONNULL_END
