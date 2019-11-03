/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/*
 Class that can be used for operating on local Mac device
 */
@interface FBMacDevice : NSObject <FBiOSTarget>

- (instancetype)initWithLogger:(id<FBControlCoreLogger>)logger;

/*
 Restores primary device state by:
 - Killling all launched process/apps
 - Removing all installed applications
 */
- (FBFuture<NSNull *> *)restorePrimaryDeviceState;

+ (NSString *)resolveDeviceUDID;

@end

NS_ASSUME_NONNULL_END
