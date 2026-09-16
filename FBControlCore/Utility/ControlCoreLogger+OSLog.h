/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/ControlCoreLogger.h>

/**
 A logger implementation on top of os_log.
 */
@interface FBControlCoreLoggerFactory (OSLog)

/**
 An os_log-backed logger, or nil when not built with an Apple compiler.
 */
+ (nullable id<ControlCoreLogger>)osLoggerWithLevel:(FBControlCoreLogLevel)level;

/**
 Returns YES if the system logger will log to stderr, NO otherwise.
 */
@property (class, nonatomic, readonly, assign) BOOL systemLoggerWillLogToStdErr;

@end
