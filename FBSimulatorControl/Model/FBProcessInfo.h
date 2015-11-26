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

@protocol FBProcessInfo <NSObject>

/**
 The Process Identifier for the running process
 */
@property (nonatomic, assign, readonly) pid_t processIdentifier;

/**
 The Launch Path of the running process
 */
@property (nonatomic, copy, readonly) NSString *launchPath;

/**
 An NSArray<NSString *> of the launch arguments of the process.
 */
@property (nonatomic, copy, readonly) NSArray *arguments;

/**
 An NSDictionary<NSString *, NSString *> of the environment of the process.
 */
@property (nonatomic, copy, readonly) NSDictionary *environment;

@end

/**
 An Object representing the current state of a process launched via FBSimulatorControl
 Implements equality to uniquely identify a launched process.
 */
@interface FBUserLaunchedProcess : NSObject <FBProcessInfo, NSCopying>

/**
 The Date the Process was launched
 */
@property (nonatomic, copy, readonly) NSDate *launchDate;

/**
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
@interface FBFoundProcess : NSObject <FBProcessInfo, NSCopying>

@end
