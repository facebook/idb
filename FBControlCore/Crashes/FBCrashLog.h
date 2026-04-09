/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBCrashLog;

@protocol FBControlCoreLogger;
@protocol FBCrashLogParser;

/**
 An emuration representing the kind of process that has crashed.
*/
typedef NS_OPTIONS(NSUInteger, FBCrashLogInfoProcessType) {
  FBCrashLogInfoProcessTypeSystem = 1 << 0, /** A process that is part of the operating system runtime */
  FBCrashLogInfoProcessTypeApplication = 1 << 1, /** A process that is an application **/
  FBCrashLogInfoProcessTypeCustom = 1 << 2, /** A process that not an application nor part of the operating system runtime **/
};

/**
 Information about Crash Logs.
 */
@interface FBCrashLogInfo : NSObject <NSCopying>

#pragma mark Properties

/**
 The "Unique" name of the crash log.
 This is taken to be the the last path component of the crash log path.
 */
@property (nonatomic, readonly, copy) NSString *name;

/**
 The Path of the Crash Log.
 */
@property (nonatomic, readonly, copy) NSString *crashPath;

/**
 The identifier of the Crash Log.
 */
@property (nonatomic, readonly, copy) NSString *identifier;

/**
 The Path of the Executable Image.
 */
@property (nonatomic, readonly, copy) NSString *executablePath;

/**
 The Name of the Crashed Process.
 */
@property (nonatomic, readonly, copy) NSString *processName;

/**
 The Process Identifier of the Crashed Process/
 */
@property (nonatomic, readonly, assign) pid_t processIdentifier;

/**
 The Process Name of the Crashed Process's parent.
 */
@property (nonatomic, readonly, copy) NSString *parentProcessName;

/**
 The Process Identifier of the Crashed Process's parent.
 */
@property (nonatomic, readonly, assign) pid_t parentProcessIdentifier;

/**
 The date of the crash
 */
@property (nonatomic, readonly, copy) NSDate *date;

/**
 The Process Type of the Crash Log
 */
@property (nonatomic, readonly, assign) FBCrashLogInfoProcessType processType;

/**
 The description of the exception
 */
@property (nullable, nonatomic, readonly, copy) NSString *exceptionDescription;

/**
 List of symbols on the crashed thread
 */
@property (nullable, nonatomic, readonly, copy) NSString *crashedThreadDescription;

#pragma mark Helpers

/**
 The Diagnostics Report Paths for the User.
 */
@property (class, nonatomic, readonly, copy) NSArray<NSString *> *diagnosticReportsPaths;

#pragma mark Initializers

/**
 Creates Crash Log Info from the specified crash log path.
 Returns nil on error.

 @param path the path to extract crash log info from.
 @param error an error out for any error that occurs.
 @return a Crash Log Info on success, nil otherwise.
 */
+ (nullable instancetype)fromCrashLogAtPath:(NSString *)path error:(NSError **)error;

#pragma mark Public Methods

/**
 Determines whether the data represents a crash log.

 @param data the data to attempt to parse.
 @return YES if it is parsable, NO otherwise.
 */
+ (BOOL)isParsableCrashLog:(NSData *)data;

#pragma mark Bulk Collection

/**
 Collects all Crash Log Info from the Default Path.

 @param date the first date to search from.
 @return an Array of all found Crash Log info.
 */
+ (NSArray<FBCrashLogInfo *> *)crashInfoAfterDate:(NSDate *)date logger:(nullable id<FBControlCoreLogger>)logger;

#pragma mark Contents

/**
 Obtains the contents of a crash log.

 @param error an error out for any error that occurs.
 @return the crash log if one could be read.
 */
- (nullable FBCrashLog *)obtainCrashLogWithError:(NSError **)error;

/**
 Reads the contents of the crash log on disk, as a string.
 */
- (nullable NSString *)loadRawCrashLogStringWithError:(NSError **)error;

#pragma mark Predicates

/**
 A Predicate for FBCrashLogInfo that passes for all Crash Logs with certain process info.

 @param processID the Process ID of the Crash to Collect.
 @return a NSPredicate.
 */
+ (NSPredicate *)predicateForCrashLogsWithProcessID:(pid_t)processID;

/**
 A Predicate for FBCrashLogInfo that passes for all Crash Logs that are newer than the given date.

 @param date the date.
 @return a NSPredicate.
 */
+ (NSPredicate *)predicateNewerThanDate:(NSDate *)date;

/**
 A Predicate for FBCrashLogInfo that passes for all Crash Logs that are older than the given date.

 @param date the date.
 @return a NSPredicate.
 */
+ (NSPredicate *)predicateOlderThanDate:(NSDate *)date;

/**
 A Predicate for FBCrashLogInfo that matches a identifier.

 @param identifier the identifier to use.
 @return an NSPredicate
 */
+ (NSPredicate *)predicateForIdentifier:(NSString *)identifier;

/**
 A Predicate for FBCrashLogInfo that matches a name.

 @param name the names use.
 @return an NSPredicate
 */
+ (NSPredicate *)predicateForName:(NSString *)name;

/**
 A Predicate that searches for a substring in the executable path.

 @param contains the substring to search for.
 @return an NSPredicate
 */
+ (NSPredicate *)predicateForExecutablePathContains:(NSString *)contains;

@end

/**
 A crash log, with it's contents.
 */
@interface FBCrashLog : NSObject <NSCopying>

#pragma mark Properties

/**
 Crash info.
 */
@property (nonatomic, readonly, copy) FBCrashLogInfo *info;

/**
 Crash contents.
 */
@property (nonatomic, readonly, copy) NSString *contents;

/// Provides date formatted to parse date strings from Apple crash logs
+ (NSDateFormatter *)dateFormatter;

@end

NS_ASSUME_NONNULL_END
