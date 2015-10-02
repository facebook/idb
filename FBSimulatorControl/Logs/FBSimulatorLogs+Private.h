/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulatorLogs.h>

@interface FBSimulatorLogs ()

@property (nonatomic, strong, readwrite) FBSimulator *simulator;

- (NSArray *)diagnosticReportsContents;

@end

@interface FBSimulatorSessionLogs ()

@property (nonatomic, strong, readwrite) FBSimulatorSession *session;

@end
