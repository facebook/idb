/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBCrashLogInfo.h"

#import <stdio.h>

#import "FBControlCoreGlobalConfiguration.h"
#import "FBDiagnostic.h"
#import "FBConcurrentCollectionOperations.h"
#import "NSPredicate+FBControlCore.h"

@implementation FBCrashLogInfo

#pragma mark Initializers

+ (instancetype)fromCrashLogAtPath:(NSString *)crashPath
{
  if (!crashPath) {
    return nil;
  }
  FILE *file = fopen(crashPath.UTF8String, "r");
  if (!file) {
    return nil;
  }

  // Buffers for the sscanf
  size_t lineSize = sizeof(char) * 4098;
  char *line = malloc(lineSize);
  char value[lineSize];

  // Values that should exist after scanning
  NSString *executablePath = nil;
  NSString *processName = nil;
  NSString *parentProcessName = nil;
  pid_t processIdentifier = -1;
  pid_t parentProcessIdentifier = -1;

  NSUInteger lineNumber = 0;
  while (lineNumber++ < 20 && getline(&line, &lineSize, file) > 0 && (processIdentifier == -1 || parentProcessIdentifier == -1)) {
    if (sscanf(line, "Process: %s [%d]", value, &processIdentifier) > 0) {
      processName = [[NSString alloc] initWithCString:value encoding:NSUTF8StringEncoding];
      continue;
    }
    if (sscanf(line, "Parent Process: %s [%d]", value, &parentProcessIdentifier) > 0) {
      parentProcessName = [[NSString alloc] initWithCString:value encoding:NSUTF8StringEncoding];
      continue;
    }
    if (sscanf(line, "Path: %s", value) > 0) {
      executablePath = [[NSString alloc] initWithCString:value encoding:NSUTF8StringEncoding];
    }
  }

  free(line);
  fclose(file);
  if (processName == nil || parentProcessName == nil || executablePath == nil || processIdentifier == -1 || parentProcessIdentifier == -1) {
    return nil;
  }

  FBCrashLogInfoProcessType processType = [self processTypeForExecutablePath:executablePath];

  return [[FBCrashLogInfo alloc]
    initWithCrashPath:crashPath
    executablePath:executablePath
    processName:processName
    processIdentifier:processIdentifier
    parentProcessName:parentProcessName
    parentProcessIdentifier:parentProcessIdentifier
    processType:processType];
}

- (instancetype)initWithCrashPath:(NSString *)crashPath executablePath:(NSString *)executablePath processName:(NSString *)processName processIdentifier:(pid_t)processIdentifer parentProcessName:(NSString *)parentProcessName parentProcessIdentifier:(pid_t)parentProcessIdentifier processType:(FBCrashLogInfoProcessType)processType
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _crashPath = crashPath;
  _executablePath = executablePath;
  _processName = processName;
  _processIdentifier = processIdentifer;
  _parentProcessName = parentProcessName;
  _parentProcessIdentifier = parentProcessIdentifier;
  _processType = processType;

  return self;
}

#pragma mark Public

- (FBDiagnostic *)toDiagnostic:(FBDiagnosticBuilder *)builder
{
  return [[[builder
    updateShortName:self.crashPath.lastPathComponent]
    updatePath:self.crashPath]
    build];
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Crash => Crash Path %@ | Executable Path %@ | Process %@ | pid %d | Parent %@ | ppid %d",
    self.crashPath,
    self.executablePath,
    self.processName,
    self.processIdentifier,
    self.parentProcessName,
    self.parentProcessIdentifier
  ];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[self.class alloc]
    initWithCrashPath:self.crashPath
    executablePath:self.executablePath
    processName:self.processName
    processIdentifier:self.processIdentifier
    parentProcessName:self.parentProcessName
    parentProcessIdentifier:self.parentProcessIdentifier
    processType:self.processType];
}

#pragma mark Bulk Collection

+ (NSArray<FBCrashLogInfo *> *)crashInfoAfterDate:(NSDate *)date
{
  NSString *basePath = self.diagnosticReportsPath;

  return [[FBConcurrentCollectionOperations
    filterMap:[NSFileManager.defaultManager contentsOfDirectoryAtPath:basePath error:nil]
    predicate:[FBCrashLogInfo predicateForFilesWithBasePath:basePath afterDate:date withExtension:@"crash"]
    map:^ FBCrashLogInfo * (NSString *fileName) {
      NSString *path = [basePath stringByAppendingPathComponent:fileName];
      return [FBCrashLogInfo fromCrashLogAtPath:path];
    }]
    filteredArrayUsingPredicate:NSPredicate.notNullPredicate];
}

#pragma mark Predicates

+ (NSPredicate *)predicateForCrashLogsWithProcessID:(pid_t)processID
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *crashLog, id _) {
    return crashLog.processIdentifier == processID;
  }];
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
  return FBCrashLogInfoProcessTypeCustomAgent;
}

+ (NSString *)diagnosticReportsPath
{
  return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/DiagnosticReports"];
}

+ (NSPredicate *)predicateForFilesWithBasePath:(NSString *)basePath afterDate:(NSDate *)date withExtension:(NSString *)extension
{
  NSFileManager *fileManager = NSFileManager.defaultManager;
  NSPredicate *datePredicate = [NSPredicate predicateWithValue:YES];
  if (date) {
    datePredicate = [NSPredicate predicateWithBlock:^ BOOL (NSString *fileName, NSDictionary *_) {
      NSString *path = [basePath stringByAppendingPathComponent:fileName];
      NSDictionary *attributes = [fileManager attributesOfItemAtPath:path error:nil];
      return [attributes.fileModificationDate isGreaterThanOrEqualTo:date];
    }];
  }
  return [NSCompoundPredicate andPredicateWithSubpredicates:@[
    [NSPredicate predicateWithFormat:@"pathExtension == %@", extension],
    datePredicate
  ]];
}

@end
