/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

/*
 Class that can be used for operating on local Mac device
 */
@interface FBMacDevice : NSObject <FBiOSTarget, FBXCTestExtendedCommands, FBProcessSpawnCommands>

- (nonnull instancetype)initWithLogger:(nonnull id<FBControlCoreLogger>)logger;

- (nonnull instancetype)initWithLogger:(nonnull id<FBControlCoreLogger>)logger catalyst:(BOOL)catalyst;

/*
 Restores primary device state by:
 - Killling all launched process/apps
 - Removing all installed applications
 */
- (nonnull FBFuture<NSNull *> *)restorePrimaryDeviceState;

@end
