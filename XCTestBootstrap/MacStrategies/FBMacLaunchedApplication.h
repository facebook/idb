/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBMacDevice;

@interface FBMacLaunchedApplication : NSObject <FBLaunchedApplication>

- (instancetype)initWithBundleID:(NSString *)bundleID
               processIdentifier:(pid_t)processIdentifier
                          device:(FBMacDevice *)device
                           queue:(dispatch_queue_t)queue;
@end

NS_ASSUME_NONNULL_END
