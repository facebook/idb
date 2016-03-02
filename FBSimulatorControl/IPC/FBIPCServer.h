/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBSimulatorSet;

/**
 The IPC Server.
 Recieves events and translates them into FBSimulatorControl API Calls.
 */
@interface FBIPCServer : NSObject

/**
 The Set that the IPC Client should respond to Remote Events for
 */
@property (nonatomic, strong, readonly) FBSimulatorSet *set;

/**
 Creates an IPC Server that manages the Simulator Set.
 */
+ (instancetype)withSimulatorSet:(FBSimulatorSet *)set;

@end
