/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBMacDevice;

@interface FBMacLaunchedApplication : NSObject <FBLaunchedApplication>

- (nonnull instancetype)initWithBundleID:(nonnull NSString *)bundleID
                       processIdentifier:(pid_t)processIdentifier
                                  device:(nonnull FBMacDevice *)device
                                   queue:(nonnull dispatch_queue_t)queue;
@end
