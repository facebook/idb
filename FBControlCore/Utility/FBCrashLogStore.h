/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

@class FBCrashLogInfo;
@protocol FBControlCoreLogger;

/**
 Stores Device Crash logs on the host.
 */
@interface FBCrashLogStore : NSObject

#pragma mark Initializers

/**
 The Designated Initializer.

 @param directory the directory to store into.
 @param logger the logger to use.
 @return a store for the device.
 */
+ (instancetype)storeForDirectory:(NSString *)directory logger:(id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 Ingest the given path.

 @param path the path to ingest.
 @return the crash log info if it exists.
 */
- (nullable FBCrashLogInfo *)ingestCrashLogAtPath:(NSString *)path;

/**
 A future that resolves the next time a crash log becomes available that matches the given predicate.

 @param predicate the predicate to use.
 @return a Future that resolves when the first crash log matching the predicate becomes available.
 */
- (FBFuture<FBCrashLogInfo *> *)nextCrashLogForMatchingPredicate:(NSPredicate *)predicate;

@end

NS_ASSUME_NONNULL_END
