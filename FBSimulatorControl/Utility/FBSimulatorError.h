/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBSimulator;

/**
 The Error Domain for FBSimulatorControl.
 */
extern NSString *const FBSimulatorControlErrorDomain;

/**
 Helpers for constructing Errors representing errors in FBSimulatorControl & adding additional diagnosis.
 */
@interface FBSimulatorError : NSObject

/**
 Describes the build error using the description.
 */
+ (instancetype)describe:(NSString *)description;
- (instancetype)describe:(NSString *)description;
+ (instancetype)describeFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (instancetype)describeFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

/*
 Adds the Cause of the Error.
 */
+ (instancetype)causedBy:(NSError *)cause;
- (instancetype)causedBy:(NSError *)cause;

/**
 For returning early from failing conditions.
 */
- (BOOL)failBool:(NSError **)error;
- (CGRect)failRect:(NSError **)error;
- (id)fail:(NSError **)error;

/**
 Attach additional diagnostic information from the Simulator.
 */
- (instancetype)inSimulator:(FBSimulator *)simulator;

/**
 Builds the Error with the applied arguments.
 */
- (NSError *)build;

@end

@interface FBSimulatorError (Constructors)

/**
 Construct a simple error with the provided description.
 */
+ (NSError *)errorForDescription:(NSString *)description;

/**
 Return NO, wrapping `failureCause` in the FBSimulatorControl domain.
 */
+ (BOOL)failBoolWithError:(NSError *)failureCause errorOut:(NSError **)errorOut;

/**
 Return NO, wraping wrapping `failureCause` in the FBSimulatorControl domain with an additional description.
 */
+ (BOOL)failBoolWithError:(NSError *)failureCause description:(NSString *)description errorOut:(NSError **)errorOut;

/**
 Return NO with a simple failure message.
 */
+ (BOOL)failBoolWithErrorMessage:(NSString *)errorMessage errorOut:(NSError **)errorOut;

/**
 Return nil with a simple failure message.
 */
+ (id)failWithErrorMessage:(NSString *)errorMessage errorOut:(NSError **)errorOut;

/**
 Return nil, wrapping `failureCause` in the FBSimulatorControl domain.
 */
+ (id)failWithError:(NSError *)failureCause errorOut:(NSError **)errorOut;

/**
 Return nil, wrapping `failureCause` in the FBSimulatorControl domain with an additional description.
 */
+ (id)failWithError:(NSError *)failureCause description:(NSString *)description errorOut:(NSError **)errorOut;

@end
