/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLogs.h"

#import <CoreSimulator/SimDevice.h>

#import "FBASLParser.h"
#import "FBCrashLogInfo.h"
#import "FBConcurrentCollectionOperations.h"
#import "FBProcessInfo.h"
#import "FBSimulator.h"
#import "FBSimulatorHistory+Queries.h"
#import "FBSimulatorLaunchInfo.h"
#import "FBSimulatorSession.h"
#import "FBTaskExecutor.h"
#import "FBWritableLog.h"

@interface FBSimulatorLogs ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorLogs

#pragma mark Initializers

+ (instancetype)withSimulator:(FBSimulator *)simulator
{
  return [[self alloc] initWithSimulator:simulator];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;

  return self;
}

#pragma mark Accessors

- (FBWritableLog *)systemLog
{
  return [[[[[FBWritableLogBuilder builder]
    updatePath:self.systemLogPath]
    updateShortName:@"system_log"]
    updateHumanReadableName:@"System Log"]
    build];
}

- (FBWritableLog *)coreSimulator
{
  return [[[[FBWritableLogBuilder builder]
    updatePath:self.coreSimulatorLogPath]
    updateHumanReadableName:@"Core Simulator Log"]
    build];
}

- (FBWritableLog *)simulatorBootstrap
{
  NSString *expectedPath = [[self.simulator.device.setPath
    stringByAppendingPathComponent:self.simulator.udid]
    stringByAppendingPathComponent:@"/data/var/run/launchd_bootstrap.plist"];

  return [[[[[FBWritableLogBuilder builder]
    updatePath:expectedPath]
    updateShortName:@"launchd_bootstrap"]
    updateHumanReadableName:@"Launchd Bootstrap"]
    build];
}

- (NSArray *)subprocessCrashesAfterDate:(NSDate *)date
{
  return [FBConcurrentCollectionOperations
    map:[self launchdSimSubprocessCrashesPathsAfterDate:date]
    withBlock:^ FBWritableLog * (FBCrashLogInfo *logInfo) {
      return [logInfo toWritableLog];
    }];
}

- (NSArray *)userLaunchedProcessCrashesSinceLastLaunch
{
  // Going from state transition to 'Booted' can be after the crash report is written for an
  // Process that instacrashes around the same time the simulator is booted.
  // Instead, use the 'Booting' state, which will be before any Process could have been launched.
  NSDate *lastLaunchDate = [[[self.simulator.history
    lastChangeOfState:FBSimulatorStateBooted]
    lastChangeOfState:FBSimulatorStateBooting]
    timestamp];

  // If we don't have the last launch date, we can't reliably predict which processes are interesting.
  if (!lastLaunchDate) {
    return @[];
  }

  return [FBConcurrentCollectionOperations
    filterMap:[self launchdSimSubprocessCrashesPathsAfterDate:lastLaunchDate]
    predicate:[FBSimulatorLogs predicateForUserLaunchedProcessesInHistory:self.simulator.history]
    map:^ FBWritableLog * (FBCrashLogInfo *logInfo) {
      return [logInfo toWritableLog];
    }];
}

- (NSDictionary *)launchedProcessLogs
{
  NSString *aslPath = self.aslPath;
  if (!aslPath) {
    return @{};
  }

  FBASLParser *aslParser = [FBASLParser parserForPath:aslPath];
  if (!aslParser) {
    return @{};
  }

  NSArray *launchedApplications = self.simulator.history.allUserLaunchedProcesses;
  NSMutableDictionary *logs = [NSMutableDictionary dictionary];
  for (FBProcessInfo *launchedProcess in launchedApplications) {
    logs[launchedProcess] = [aslParser writableLogForProcessInfo:launchedProcess];
  }

  return [logs copy];
}

#pragma mark Private

- (NSString *)systemLogPath
{
  return [self.simulator.device.logPath stringByAppendingPathComponent:@"system.log"];
}

- (NSString *)coreSimulatorLogPath
{
  return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/CoreSimulator/CoreSimulator.log"];
}

- (NSString *)diagnosticReportsPath
{
  return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/DiagnosticReports"];
}

- (NSString *)aslPath
{
  NSString *basePath = [[[NSHomeDirectory()
    stringByAppendingPathComponent:@"Library/Logs/CoreSimulator"]
    stringByAppendingPathComponent:self.simulator.udid]
    stringByAppendingPathComponent:@"asl"];

  NSFileManager *fileManager = NSFileManager.defaultManager;

  BOOL isDirectory = NO;
  if (![fileManager fileExistsAtPath:basePath isDirectory:&isDirectory]) {
    return nil;
  }
  if (!isDirectory) {
    return nil;
  }

  NSString *file = [[[[NSFileManager.defaultManager
    contentsOfDirectoryAtPath:basePath error:nil]
    pathsMatchingExtensions:@[@"asl"]]
    sortedArrayUsingComparator:[FBSimulatorLogs fileSizeComparatorAtBasePath:basePath]]
    firstObject];

  if (!file) {
    return nil;
  }

  return [basePath stringByAppendingPathComponent:file];
}

- (NSArray *)crashInfoAfterDate:(NSDate *)date
{
  NSString *basePath = self.diagnosticReportsPath;

  return [FBConcurrentCollectionOperations
    filterMap:[NSFileManager.defaultManager contentsOfDirectoryAtPath:basePath error:nil]
    predicate:[FBSimulatorLogs predicateForFilesWithBasePath:basePath afterDate:date withExtension:@"crash"]
    map:^ FBCrashLogInfo * (NSString *fileName) {
      NSString *path = [basePath stringByAppendingPathComponent:fileName];
      return [FBCrashLogInfo fromCrashLogAtPath:path];
    }];
}

- (NSArray *)launchdSimSubprocessCrashesPathsAfterDate:(NSDate *)date
{
  FBProcessInfo *launchdProcess = self.simulator.launchInfo.launchdProcess;
  if (!launchdProcess) {
    return @[];
  }

  NSPredicate *parentProcessPredicate = [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *logInfo, NSDictionary *_) {
    return [logInfo.parentProcessName isEqualToString:@"launchd_sim"] && logInfo.parentProcessIdentifier == launchdProcess.processIdentifier;
  }];

  return [[self crashInfoAfterDate:date] filteredArrayUsingPredicate:parentProcessPredicate];
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

+ (NSPredicate *)predicateForUserLaunchedProcessesInHistory:(FBSimulatorHistory *)history
{
  NSSet *pidSet = [NSSet setWithArray:[history.allUserLaunchedProcesses valueForKey:@"processIdentifier"]];
  return [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *crashLog, NSDictionary *_) {
    return [pidSet containsObject:@(crashLog.processIdentifier)];
  }];
}

+ (NSComparator)fileSizeComparatorAtBasePath:(NSString *)basePath
{
  NSFileManager *fileManager = NSFileManager.defaultManager;

  return ^ NSComparisonResult (NSString *leftFilename, NSString *rightFilename) {
    NSDictionary *leftAttributes = [fileManager attributesOfItemAtPath:[basePath stringByAppendingPathComponent:leftFilename] error:nil];
    NSDictionary *rightAttributes = [fileManager attributesOfItemAtPath:[basePath stringByAppendingPathComponent:rightFilename] error:nil];
    if (leftAttributes.fileSize == rightAttributes.fileSize) {
      return NSOrderedSame;
    }
    if (leftAttributes.fileSize > rightAttributes.fileSize) {
      return NSOrderedAscending;
    }
    return NSOrderedDescending;
  };
}

@end
