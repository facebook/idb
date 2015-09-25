/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBSimulatorSessionState.h>

@interface FBSimulatorSessionState ()

@property (nonatomic, weak, readwrite) FBSimulatorSession *session;
@property (nonatomic, copy, readwrite) FBSimulatorSessionState *previousState;

@property (nonatomic, copy, readwrite) NSDate *timestamp;
@property (nonatomic, assign, readwrite) FBSimulatorSessionLifecycleState lifecycle;
@property (nonatomic, assign, readwrite) FBSimulatorState simulatorState;
@property (nonatomic, strong, readwrite) NSMutableOrderedSet *runningProcessesSet;
@property (nonatomic, strong, readwrite) NSMutableDictionary *mutableDiagnostics;

@end
