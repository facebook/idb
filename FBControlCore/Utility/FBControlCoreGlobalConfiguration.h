/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@protocol FBControlCoreLogger;

/**
 An Environment Variable: 'FBCONTROLCORE_LOGGING' to enable logging of Informational Messages to stderr.
 */
extern NSString * _Nonnull const FBControlCoreStderrLogging;

/**
 An Environment Variable: 'FBCONTROLCORE_DEBUG_LOGGING' to enable logging of Debug Messages to stderr.
 */
extern NSString * _Nonnull const FBControlCoreDebugLogging;

/**
 Environment Globals & other derived constants.
 These values can be accessed before the Private Frameworks are loaded.
 */
@interface FBControlCoreGlobalConfiguration : NSObject

/**
 A Timeout Value when waiting on events that should happen 'fast'
 */
@property (class, nonatomic, readonly, assign) NSTimeInterval fastTimeout;

/**
 A Timeout Value when waiting on events that will take some time longer than 'fast' events.
 */
@property (class, nonatomic, readonly, assign) NSTimeInterval regularTimeout;

/**
 A Timeout Value when waiting on events that will a longer period of time.
 */
@property (class, nonatomic, readonly, assign) NSTimeInterval slowTimeout;

/**
 A Description of the Current Configuration.
 */
@property (class, nonnull, nonatomic, readonly, copy) NSString *description;

/**
 The default logger to send log messages to.
 */
@property (class, nonnull, nonatomic, readwrite, strong) id<FBControlCoreLogger> defaultLogger;

/**
 Confirm the existence of code signatures, where relevant.
 */
@property (class, nonatomic, readonly, assign) BOOL confirmCodesignaturesAreValid;

/**
 Environment in this process that should be passed down to child processes.
 */
@property (class, nonnull, nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *safeSubprocessEnvironment;

@end
