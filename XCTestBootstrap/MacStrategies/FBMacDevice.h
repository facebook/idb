/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/FBDeviceOperator.h>

NS_ASSUME_NONNULL_BEGIN

/*
 Class that can be used for operating on local Mac device
 */
@interface FBMacDevice : NSObject <FBDeviceOperator, FBiOSTarget>

- (instancetype)initWithLogger:(id<FBControlCoreLogger>)logger;

/*
 Restores primary device state by:
 - Killling all launched process/apps
 - Removing all installed applications
 */
- (FBFuture<NSNull *> *)restorePrimaryDeviceState;

@end

NS_ASSUME_NONNULL_END
