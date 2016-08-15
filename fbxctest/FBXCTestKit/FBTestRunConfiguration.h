/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBSimulatorConfiguration;
@protocol FBControlCoreLogger;
@protocol FBXCTestReporter;

@interface FBTestRunConfiguration : NSObject
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) id<FBXCTestReporter> reporter;
@property (nonatomic, strong, readonly) FBSimulatorConfiguration *targetDeviceConfiguration;

@property (nonatomic, copy, readonly) NSString *workingDirectory;
@property (nonatomic, copy, readonly) NSString *testBundlePath;
@property (nonatomic, copy, readonly) NSString *runnerAppPath;
@property (nonatomic, copy, readonly) NSString *simulatorName;
@property (nonatomic, copy, readonly) NSString *simulatorOS;

@property (nonatomic, assign, readonly) BOOL runWithoutSimulator;

- (BOOL)loadWithArguments:(NSArray<NSString *> *)arguments workingDirectory:(NSString *)workingDirectory error:(NSError **)error;

@end
