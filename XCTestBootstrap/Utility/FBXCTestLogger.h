/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A logger for FBXCTest that accumilates messages, but can be used for logging in the event a failure occurs.
 */
@interface FBXCTestLogger : NSObject <FBControlCoreLogger>

/**
 A Test Logger that will write to a default directory.

 @return a new FBXCTestLogger Instance
 */
+ (instancetype)defaultLoggerInDefaultDirectory;

/**
 A Test Logger that will write to a default directory.

 @param name a unique name for the logger.
 @return a new FBXCTestLogger Instance
 */
+ (instancetype)loggerInDefaultDirectory:(NSString *)name;

/**
 A Test Logger that will write to a specified directory.

 @param directory the directory to log into.
 @return a new FBXCTestLogger Instance
 */
+ (instancetype)defaultLoggerInDirectory:(NSString *)directory;

/**
 A Test Logger with the specified name and directory.

 @param directory the directory to log into.
 @param name a unique name for the logger.
 @return a new FBXCTestLogger Instance
 */
+ (instancetype)loggerInDirectory:(NSString *)directory name:(NSString *)name;

/**
 Logs the Consumption of the consumer to a file

 @param consumer the consumer to wrap.
 @param fileName file to be written.
 @param logger the logger to log the mirrored path to.
 @return a Future that resolves with the new consumer.
 */
- (FBFuture<id<FBDataConsumer, FBDataConsumerLifecycle>> *)logConsumptionOf:(id<FBDataConsumer>)consumer toFileNamed:(NSString *)fileName logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
