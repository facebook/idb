/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBProcessLaunchConfiguration;

@protocol FBSimulatorProcess <NSObject>

/**
 The Process Identifier for the running process
 */
@property (nonatomic, assign, readonly) pid_t processIdentifier;

/**
 The Launch Path of the running process
 */
@property (nonatomic, copy, readonly) NSString *launchPath;

@end

/**
 An Object representing the current state of a process launched via FBSimulatorControl
 Implements equality to uniquely identify a launched process.
 */
@interface FBUserLaunchedProcess : NSObject <FBSimulatorProcess, NSCopying>

/**
 The Date the Process was launched
 */
@property (nonatomic, copy, readonly) NSDate *launchDate;

/**
 The Launch Config of the Launched Process
 */
@property (nonatomic, copy, readonly) FBProcessLaunchConfiguration *launchConfiguration;

/**
 A key-value store of arbitrary diagnostic information for the process
 */
@property (nonatomic, copy, readonly) NSDictionary *diagnostics;

@end

/**
 An Object representing the current state of a process launched automatically by the Simulator.
 Implements equality to uniquely identify a launched process.
 */
@interface FBFoundProcess : NSObject <FBSimulatorProcess, NSCopying>

+ (instancetype)withProcessIdentifier:(pid_t)processIdentifier launchPath:(NSString *)launchPath;

@end
