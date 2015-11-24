/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulatorProcess.h>

@interface FBUserLaunchedProcess ()

@property (nonatomic, assign, readwrite) pid_t processIdentifier;
@property (nonatomic, copy, readwrite) NSDate *launchDate;
@property (nonatomic, copy, readwrite) FBProcessLaunchConfiguration *launchConfiguration;
@property (nonatomic, copy, readwrite) NSDictionary *diagnostics;

@end

@interface FBFoundProcess ()

@property (nonatomic, assign, readwrite) pid_t processIdentifier;
@property (nonatomic, copy, readwrite) NSString *launchPath;

@end
