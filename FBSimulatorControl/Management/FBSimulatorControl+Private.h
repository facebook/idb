/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

@interface FBSimulatorControl ()

@property (nonatomic, copy, readwrite) FBSimulatorControlConfiguration *configuration;

@property (nonatomic, strong, readwrite) FBSimulatorSession *activeSession;
@property (nonatomic, strong, readwrite) FBSimulatorPool *simulatorPool;
@property (nonatomic, assign, readwrite) BOOL hasRunOnce;

- (instancetype)initWithConfiguration:(FBSimulatorControlConfiguration *)configuration;

+ (NSError *)errorForDescription:(NSString *)description;
+ (BOOL)failBoolWithError:(NSError *)failureCause errorOut:(NSError **)errorOut;
+ (BOOL)failBoolWithError:(NSError *)failureCause description:(NSString *)description errorOut:(NSError **)errorOut;
+ (BOOL)failBoolWithErrorMessage:(NSString *)errorMessage errorOut:(NSError **)errorOut;

+ (id)failWithErrorMessage:(NSString *)errorMessage errorOut:(NSError **)errorOut;
+ (id)failWithError:(NSError *)failureCause errorOut:(NSError **)errorOut;
+ (id)failWithError:(NSError *)failureCause description:(NSString *)description errorOut:(NSError **)errorOut;

@end
