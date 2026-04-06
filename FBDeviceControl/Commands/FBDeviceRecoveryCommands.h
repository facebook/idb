/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@protocol FBDeviceRecoveryCommandsProtocol <FBiOSTargetCommand>

- (nonnull FBFuture<NSNull *> *)enterRecovery;
- (nonnull FBFuture<NSNull *> *)exitRecovery;

@end
