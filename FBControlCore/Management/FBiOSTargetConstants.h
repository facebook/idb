/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 An enum representing states. The values here are not guaranteed to be stable over time and should not be serialized.
 FBiOSTargetStateString is guaranteed to be stable over time.
 */
typedef NS_ENUM(NSUInteger, FBiOSTargetState) {
  FBiOSTargetStateCreating = 0,
  FBiOSTargetStateShutdown = 1,
  FBiOSTargetStateBooting = 2,
  FBiOSTargetStateBooted = 3,
  FBiOSTargetStateShuttingDown = 4,
  FBiOSTargetStateDFU = 5,
  FBiOSTargetStateRecovery = 6,
  FBiOSTargetStateRestoreOS = 7,
  FBiOSTargetStateUnknown = 99,
};

/**
 Represents the kind of a target.
 */
typedef NS_ENUM(NSUInteger, FBiOSTargetType) {
  FBiOSTargetTypeNone = 0,
  FBiOSTargetTypeSimulator = 1 << 0,
  FBiOSTargetTypeDevice = 1 << 1,
  FBiOSTargetTypeLocalMac = 1 << 2,
};

/**
 String representations of FBiOSTargetState.
 */
typedef NSString *FBiOSTargetStateString NS_STRING_ENUM;
extern FBiOSTargetStateString const FBiOSTargetStateStringCreating;
extern FBiOSTargetStateString const FBiOSTargetStateStringShutdown;
extern FBiOSTargetStateString const FBiOSTargetStateStringBooting;
extern FBiOSTargetStateString const FBiOSTargetStateStringBooted;
extern FBiOSTargetStateString const FBiOSTargetStateStringShuttingDown;
extern FBiOSTargetStateString const FBiOSTargetStateStringDFU;
extern FBiOSTargetStateString const FBiOSTargetStateStringRecovery;
extern FBiOSTargetStateString const FBiOSTargetStateStringRestoreOS;
extern FBiOSTargetStateString const FBiOSTargetStateStringUnknown;

NS_ASSUME_NONNULL_END
