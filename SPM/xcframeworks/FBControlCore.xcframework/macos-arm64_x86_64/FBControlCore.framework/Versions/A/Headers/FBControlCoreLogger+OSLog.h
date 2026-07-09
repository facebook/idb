/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCoreLogger.h>

/**
 A logger implementation on top of os_log.
 */
@interface FBControlCoreLoggerFactory (OSLog)

/*
 Construct a new OS Log logger.

 @pragma mark level the log level to use.
 @return a new logger logging to os_log.
 */
+ (nullable id<FBControlCoreLogger>)osLoggerWithLevel:(FBControlCoreLogLevel)level;

/**
 Returns YES if the system logger will log to stderr, NO otherwise.
 */
@property (class, nonatomic, readonly, assign) BOOL systemLoggerWillLogToStdErr;

@end
