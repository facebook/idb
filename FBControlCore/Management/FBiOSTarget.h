/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

/**
 Uses the known values of SimDevice State, to construct an enumeration.
 These mirror the values from -[SimDeviceState state].
 */
typedef NS_ENUM(NSUInteger, FBSimulatorState) {
  FBSimulatorStateCreating = 0,
  FBSimulatorStateShutdown = 1,
  FBSimulatorStateBooting = 2,
  FBSimulatorStateBooted = 3,
  FBSimulatorStateShuttingDown = 4,
  FBSimulatorStateUnknown = 99,
};

NS_ASSUME_NONNULL_BEGIN

/**
 Common Properties of Devices & Simulators.
 */
@protocol FBiOSTarget <NSObject>

/**
 The Unique Device Identifier of the iOS Target.
 */
@property (nonatomic, copy, readonly, nonnull) NSString *udid;

@end

/**
 The canonical string representation of the state enum.
 */
extern NSString *FBSimulatorStateStringFromState(FBSimulatorState state);

/**
 The canonical enum representation of the state string.
 */
extern FBSimulatorState FBSimulatorStateFromStateString(NSString *stateString);

NS_ASSUME_NONNULL_END
