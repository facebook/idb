/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

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
extern FBiOSTargetStateString _Nonnull const FBiOSTargetStateStringCreating;
extern FBiOSTargetStateString _Nonnull const FBiOSTargetStateStringShutdown;
extern FBiOSTargetStateString _Nonnull const FBiOSTargetStateStringBooting;
extern FBiOSTargetStateString _Nonnull const FBiOSTargetStateStringBooted;
extern FBiOSTargetStateString _Nonnull const FBiOSTargetStateStringShuttingDown;
extern FBiOSTargetStateString _Nonnull const FBiOSTargetStateStringDFU;
extern FBiOSTargetStateString _Nonnull const FBiOSTargetStateStringRecovery;
extern FBiOSTargetStateString _Nonnull const FBiOSTargetStateStringRestoreOS;
extern FBiOSTargetStateString _Nonnull const FBiOSTargetStateStringUnknown;
