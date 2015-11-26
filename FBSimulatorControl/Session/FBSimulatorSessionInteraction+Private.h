/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBSimulatorSessionInteraction.h>

extern NSTimeInterval const FBSimulatorInteractionDefaultTimeout;

@interface FBSimulatorSessionInteraction ()

@property (nonatomic, strong) FBSimulatorSession *session;

/**
 Chains an interaction on an application process, for the given application.
 */
- (instancetype)application:(FBSimulatorApplication *)application interact:(BOOL (^)(pid_t processIdentifier, NSError **error))block;

@end
