/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import "FBSimulatorSessionState.h"

@class FBDispatchSourceNotifier;

@interface FBSimulatorSessionProcessState ()

@property (nonatomic, assign, readwrite) NSInteger processIdentifier;
@property (nonatomic, copy, readwrite) NSDate *launchDate;
@property (nonatomic, copy, readwrite) FBProcessLaunchConfiguration *launchConfiguration;
@property (nonatomic, copy, readwrite) NSDictionary *diagnostics;


@end

@interface FBSimulatorSessionState ()

@property (nonatomic, weak, readwrite) FBSimulatorSession *session;
@property (nonatomic, copy, readwrite) FBSimulatorSessionState *previousState;

@property (nonatomic, assign, readwrite) FBSimulatorSessionLifecycleState lifecycle;
@property (nonatomic, strong, readwrite) NSMutableOrderedSet *runningProcessesSet;

@end
