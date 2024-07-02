/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBCrashLog.h"

#import <stdio.h>

#import "FBControlCoreGlobalConfiguration.h"
#import "FBConcurrentCollectionOperations.h"
#import "NSPredicate+FBControlCore.h"
#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"
#import "FBConcatedJsonParser.h"
#import "FBCrashLogParser.h"
#import <Foundation/Foundation.h>

@implementation FBCrashLog


+ (NSDateFormatter *)dateFormatter
{
  static dispatch_once_t onceToken;
  static NSDateFormatter *dateFormatter = nil;
  dispatch_once(&onceToken, ^{
    dateFormatter = [NSDateFormatter new];
    dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS Z";
    dateFormatter.lenient = YES;
    dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
  });
  return dateFormatter;
}

#pragma mark Initializers

- (instancetype)initWithInfo:(FBCrashLogInfo *)info contents:(NSString *)contents
{
  self = [super init];
  if (!self) {
      return nil;
  }

  _info = info;
  _contents = contents;

  return self;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Crash Info: %@ \n Crash Report: %@\n", _info, _contents];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
    // Is immutable
    return self;
}

@end

@implementation FBCrashLogInfo

#pragma mark Initializers

+ (nullable instancetype)fromCrashLogAtPath:(NSString *)crashPath error:(NSError **)error {
  if (!crashPath) {
    return [[FBControlCoreError
      describe:@"No crash path provided"]
      fail:error];
  }
  if (![NSFileManager.defaultManager fileExistsAtPath:crashPath]) {
    return [[FBControlCoreError
      describeFormat:@"File does not exist at given crash path: %@", crashPath]
      fail:error];
  }
  if (![NSFileManager.defaultManager isReadableFileAtPath:crashPath]) {
    return [[FBControlCoreError
      describeFormat:@"Crash file at %@ is not readable", crashPath]
      fail:error];
  }
  NSData *crashFileData = [NSData dataWithContentsOfFile:crashPath options:0 error:error];
  if (!crashFileData) {
    return [[FBControlCoreError
      describeFormat:@"Could not read data from %@", crashPath]
      fail:error];
  } else if (crashFileData.length == 0) {
      return [[FBControlCoreError
        describeFormat:@"Crash file at %@ is empty", crashPath]
        fail:error];
  }

  NSString *crashString = [[NSString alloc] initWithData:crashFileData encoding:NSUTF8StringEncoding];
  if (!crashString) {
    return [[FBControlCoreError
      describeFormat:@"Could not extract string from %@", crashPath]
      fail:error];
  }

  return [self fromCrashLogString:crashString crashPath:crashPath parser:[self getPreferredCrashLogParserForCrashString:crashString] error:error];
}

+ (id<FBCrashLogParser>)getPreferredCrashLogParserForCrashString:(NSString *)crashString {
  if (crashString.length > 0 && [crashString characterAtIndex:0] == '{') {
    return [[FBConcatedJSONCrashLogParser alloc] init];
  } else {
    return [[FBPlainTextCrashLogParser alloc] init];
  }
}

+ (nullable instancetype)fromCrashLogString:(NSString *)crashString crashPath:(NSString *)crashPath parser:(id<FBCrashLogParser>)parser error:(NSError **)error {

  NSString *executablePath = nil;
  NSString *identifier = nil;
  NSString *processName = nil;
  NSString *parentProcessName = nil;
  NSDate *date = nil;
  pid_t processIdentifier = -1;
  pid_t parentProcessIdentifier = -1;
  NSString *exceptionDescription = nil;
  NSString *crashedThreadDescription = nil;

  NSError *err;
  [parser parseCrashLogFromString:crashString
    executablePathOut:&executablePath
    identifierOut:&identifier
    processNameOut:&processName
    parentProcessNameOut:&parentProcessName
    processIdentifierOut:&processIdentifier
    parentProcessIdentifierOut:&parentProcessIdentifier
    dateOut:&date
    exceptionDescription:&exceptionDescription
    crashedThreadDescription:&crashedThreadDescription
    error:&err];

  if (err) {
    return [[FBControlCoreError
             describeFormat:@"Could not parse crash string %@", err]
            fail:error];
  }

  if (processName == nil) {
    return [[FBControlCoreError
             describe:@"Missing process name in crash log"]
            fail:error];
  }
  if (identifier == nil) {
    return [[FBControlCoreError
             describe:@"Missing identifier in crash log"]
            fail:error];
  }
  if (parentProcessName == nil) {
    return [[FBControlCoreError
             describe:@"Missing process name in crash log"]
            fail:error];
  }
  if (executablePath == nil) {
    return [[FBControlCoreError
             describe:@"Missing executable path in crash log"]
            fail:error];
  }
  if (processIdentifier == -1) {
    return [[FBControlCoreError
             describe:@"Missing process identifier in crash log"]
            fail:error];
  }
  if (parentProcessIdentifier == -1) {
    return [[FBControlCoreError
             describe:@"Missing parent process identifier in crash log"]
            fail:error];
  }
  if (date == nil) {
    return [[FBControlCoreError
             describe:@"Missing date in crash log"]
            fail:error];
  }

  FBCrashLogInfoProcessType processType = [self processTypeForExecutablePath:executablePath];

  return [[FBCrashLogInfo alloc]
    initWithCrashPath:crashPath
    executablePath:executablePath
    identifier:identifier
    processName:processName
    processIdentifier:processIdentifier
    parentProcessName:parentProcessName
    parentProcessIdentifier:parentProcessIdentifier
    date:date
    processType:processType
    exceptionDescription:exceptionDescription
    crashedThreadDescription:crashedThreadDescription];
}


- (instancetype)initWithCrashPath:(NSString *)crashPath executablePath:(NSString *)executablePath identifier:(NSString *)identifier processName:(NSString *)processName processIdentifier:(pid_t)processIdentifer parentProcessName:(NSString *)parentProcessName parentProcessIdentifier:(pid_t)parentProcessIdentifier date:(NSDate *)date processType:(FBCrashLogInfoProcessType)processType exceptionDescription:(NSString *)exceptionDescription crashedThreadDescription:(NSString *)crashedThreadDescription{
  self = [super init];
  if (!self) {
    return nil;
  }

  _crashPath = crashPath;
  _executablePath = executablePath;
  _identifier = identifier;
  _processName = processName;
  _processIdentifier = processIdentifer;
  _parentProcessName = parentProcessName;
  _parentProcessIdentifier = parentProcessIdentifier;
  _date = date;
  _processType = processType;
  _exceptionDescription = exceptionDescription;
  _crashedThreadDescription = crashedThreadDescription;

  return self;
}

#pragma mark Public

+ (BOOL)isParsableCrashLog:(NSData *)data
{
#if defined(__apple_build_version__)
  NSString *crashString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  FBCrashLogInfo *parsable = [self fromCrashLogString:crashString crashPath:@"" parser:[self getPreferredCrashLogParserForCrashString:crashString] error:nil];
  return parsable != nil;
#else
  return NO;
#endif
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Identifier %@ | Executable Path %@ | Process %@ | pid %d | Parent %@ | ppid %d | Date %@ | Path %@ | Exception: %@ | Trace: %@",
    self.identifier,
    self.executablePath,
    self.processName,
    self.processIdentifier,
    self.parentProcessName,
    self.parentProcessIdentifier,
    self.date,
    self.crashPath,
    self.exceptionDescription,
    self.crashedThreadDescription
  ];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  // Is immutable
  return self;
}

#pragma mark Properties

- (NSString *)name
{
  return self.crashPath.lastPathComponent;
}

- (nullable NSString *)loadRawCrashLogStringWithError:(NSError **)error;
{
  return [NSString stringWithContentsOfFile:self.crashPath encoding:NSUTF8StringEncoding error:error];
}

#pragma mark Bulk Collection

+ (NSArray<FBCrashLogInfo *> *)crashInfoAfterDate:(NSDate *)date logger:(id<FBControlCoreLogger>)logger
{
  NSMutableArray<FBCrashLogInfo *> *allCrashInfos = NSMutableArray.new;

  for (NSString *basePath in self.diagnosticReportsPaths) {
    NSArray<FBCrashLogInfo *> *crashInfos = [[FBConcurrentCollectionOperations
      filterMap:[NSFileManager.defaultManager contentsOfDirectoryAtPath:basePath error:nil]
      predicate:[FBCrashLogInfo predicateForFilesWithBasePath:basePath afterDate:date withExtension:@"crash"]
      map:^ FBCrashLogInfo * (NSString *fileName) {
        NSString *path = [basePath stringByAppendingPathComponent:fileName];
        NSError *error = nil;
        FBCrashLogInfo *info = [FBCrashLogInfo fromCrashLogAtPath:path error:&error];
        if (!info) {
          [logger logFormat:@"Error parsing log %@", error];
        }
        return info;
      }]
      filteredArrayUsingPredicate:NSPredicate.notNullPredicate];

    [allCrashInfos addObjectsFromArray:crashInfos];
  }

  return [allCrashInfos copy];
}

#pragma mark Contents

- (FBCrashLog *)obtainCrashLogWithError:(NSError **)error
{
  NSError *innerError = nil;
  NSString *contents = [self loadRawCrashLogStringWithError:&innerError];
  if (!contents) {
    return [[[FBControlCoreError
      describeFormat:@"Failed to read crash log at path %@", self.crashPath]
      causedBy:innerError]
      fail:error];
  }
  return [[FBCrashLog alloc] initWithInfo:self contents:contents];
}

#pragma mark Predicates

+ (NSPredicate *)predicateForCrashLogsWithProcessID:(pid_t)processID
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *crashLog, id _) {
    return crashLog.processIdentifier == processID;
  }];
}

+ (NSPredicate *)predicateNewerThanDate:(NSDate *)date
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *crashLog, id _) {
    return [date compare:crashLog.date] == NSOrderedAscending;
  }];
}

+ (NSPredicate *)predicateOlderThanDate:(NSDate *)date
{
  return [NSCompoundPredicate notPredicateWithSubpredicate:[self predicateNewerThanDate:date]];
}

+ (NSPredicate *)predicateForIdentifier:(NSString *)identifier
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *crashLog, id _) {
    return [identifier isEqualToString:crashLog.identifier];
  }];
}

+ (NSPredicate *)predicateForName:(NSString *)name
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *crashLog, id _) {
    return [name isEqualToString:crashLog.name];
  }];
}

+ (NSPredicate *)predicateForExecutablePathContains:(NSString *)contains
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *crashLog, id _) {
    return [crashLog.executablePath containsString:contains];
  }];
}

#pragma mark Helpers

+ (NSArray<NSString *> *)diagnosticReportsPaths
{
  return @[
    [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/DiagnosticReports"],
    @"/Library/Logs/DiagnosticReports", // diagnostic reports path when ReportCrash is running as root.
  ];
}

#pragma mark Private

+ (FBCrashLogInfoProcessType)processTypeForExecutablePath:(NSString *)executablePath
{
  if ([executablePath containsString:@"Platforms/iPhoneSimulator.platform"]) {
    return FBCrashLogInfoProcessTypeSystem;
  }
  if ([executablePath containsString:@".app"]) {
    return FBCrashLogInfoProcessTypeApplication;
  }
  return FBCrashLogInfoProcessTypeCustom;
}

+ (NSPredicate *)predicateForFilesWithBasePath:(NSString *)basePath afterDate:(NSDate *)date withExtension:(NSString *)extension
{
  NSFileManager *fileManager = NSFileManager.defaultManager;
  NSPredicate *datePredicate = [NSPredicate predicateWithValue:YES];
  if (date) {
    datePredicate = [NSPredicate predicateWithBlock:^ BOOL (NSString *fileName, NSDictionary *_) {
      NSString *path = [basePath stringByAppendingPathComponent:fileName];
      NSDictionary *attributes = [fileManager attributesOfItemAtPath:path error:nil];
      return [attributes.fileModificationDate compare:date] != NSOrderedAscending;
    }];
  }
  return [NSCompoundPredicate andPredicateWithSubpredicates:@[
    [NSPredicate predicateWithFormat:@"pathExtension == %@", extension],
    datePredicate
  ]];
}

@end
