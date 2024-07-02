/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

 @param directories the directories to store into.
 @param logger the logger to use.
 @return a store for the device.
 */
+ (instancetype)storeForDirectories:(NSArray<NSString *> *)directories logger:(id<FBControlCoreLogger>)logger;

#pragma mark Ingestion

/**
 Ingests all of the crash logs in the directory.

 @return all the crash logs that have just been ingested.
 */
- (NSArray<FBCrashLogInfo *> *)ingestAllExistingInDirectory;

/**
 Ingest the given path.

 @param path the path to ingest.
 @return the crash log info if it exists.
 */
- (nullable FBCrashLogInfo *)ingestCrashLogAtPath:(NSString *)path;

/**
 Ingest the given data.

 @param data the data to ingest.
 @param name the name of the crash log.
 @return the crash log info if it exists.
 */
- (nullable FBCrashLogInfo *)ingestCrashLogData:(NSData *)data name:(NSString *)name;

/**
 Removes the crash log at at a given path.

 @param path the path of the crash log to remove
 @return the crash log info if one exists.
 */
- (nullable FBCrashLogInfo *)removeCrashLogAtPath:(NSString *)path;

#pragma mark Fetching

/**
 Returns the ingested crash log for a given name

 @param name the name of the crash log.
 @return the Crash Log Info, if present.
 */
- (nullable FBCrashLogInfo *)ingestedCrashLogWithName:(NSString *)name;

/**
 Returns all of the ingested crash logs.

 @return all of the ingested crash logs.
 */
- (NSArray<FBCrashLogInfo *> *)allIngestedCrashLogs;

/**
 A future that resolves the next time a crash log becomes available that matches the given predicate.

 @param predicate the predicate to use.
 @return a Future that resolves when the first crash log matching the predicate becomes available.
 */
- (FBFuture<FBCrashLogInfo *> *)nextCrashLogForMatchingPredicate:(NSPredicate *)predicate;

/**
 Obtains all of the ingested logs that match the given predicate.

 @param predicate the predicate to use.
 @return an array of all the ingested crash logs.
 */
- (NSArray<FBCrashLogInfo *> *)ingestedCrashLogsMatchingPredicate:(NSPredicate *)predicate;

/**
 Prunes all of the ingested logs that match the given predicate.

 @param predicate the predicate to use.
 @return an array of all the pruned crash logs.
 */
- (NSArray<FBCrashLogInfo *> *)pruneCrashLogsMatchingPredicate:(NSPredicate *)predicate;

@end

NS_ASSUME_NONNULL_END
