/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 Raw values are not stable across versions and must not be serialized; the Swift `TargetStateString` form is.
 */
typedef NS_ENUM(NSUInteger, FBTargetState) {
  FBTargetStateCreating = 0,
  FBTargetStateShutdown = 1,
  FBTargetStateBooting = 2,
  FBTargetStateBooted = 3,
  FBTargetStateShuttingDown = 4,
  FBTargetStateDFU = 5,
  FBTargetStateRecovery = 6,
  FBTargetStateRestoreOS = 7,
  FBTargetStateUnknown = 99,
};

/**
 Represents the kind of a target.
 */
typedef NS_ENUM(NSUInteger, FBTargetType) {
  FBTargetTypeNone = 0,
  FBTargetTypeSimulator = 1 << 0,
  FBTargetTypeDevice = 1 << 1,
  FBTargetTypeLocalMac = 1 << 2,
};
