/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLogs.h"
#import "FBSimulatorLogs+Private.h"

#import <CoreSimulator/SimDevice.h>

#import "FBConcurrentCollectionOperations.h"
#import "FBProcessInfo.h"
#import "FBSimulator.h"
#import "FBSimulatorHistory+Queries.h"
#import "FBSimulatorLaunchInfo.h"
#import "FBSimulatorSession.h"
#import "FBTaskExecutor.h"
#import "FBWritableLog.h"

@implementation FBSimulatorLogs

#pragma mark Initializers

+ (instancetype)withSimulator:(FBSimulator *)simulator
{
  FBSimulatorLogs *logs = [self new];
  logs.simulator = simulator;
  return logs;
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
    withBlock:^ FBWritableLog * (NSString *path) {
      return [[[FBWritableLogBuilder builder]
        updatePath:path]
        build];
    }];
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

- (NSArray *)diagnosticReportsContents
{
  return [NSFileManager.defaultManager subpathsAtPath:self.diagnosticReportsPath];
}

/**
 It is possible to search for the Simulator UUID inside the Crash Reports, but this only works for the Default Set.
 Custom DeviceSets do not have the Simulator UUID, or even the path to the the launched Executable Image.
 It is possible to filter the results of this to ensure that the crash report is a relevant Application and not some Simulator Service.
 */
- (NSArray *)launchdSimSubprocessCrashesPathsAfterDate:(NSDate *)date
{
  FBProcessInfo *launchdProcess = self.simulator.launchInfo.launchdProcess;
  if (!launchdProcess) {
    return @[];
  }

  NSString *needle = [NSString stringWithFormat:@"launchd_sim [%d]", launchdProcess.processIdentifier];
  NSPredicate *simulatorPredicate = [NSPredicate predicateWithBlock:^ BOOL (NSString *path, NSDictionary *_) {
    NSString *fileContents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    return [fileContents rangeOfString:needle].location != NSNotFound;
  }];

  NSFileManager *fileManager = NSFileManager.defaultManager;
  NSPredicate *datePredicate = [NSPredicate predicateWithValue:YES];
  if (date) {
    datePredicate = [NSPredicate predicateWithBlock:^ BOOL (NSString *path, NSDictionary *_) {
      NSDictionary *attributes = [fileManager attributesOfItemAtPath:path error:nil];
      return [attributes.fileModificationDate isGreaterThanOrEqualTo:date];
    }];
  }

  NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[
    datePredicate,
    simulatorPredicate
  ]];

  NSString *basePath = self.diagnosticReportsPath;
  return [FBConcurrentCollectionOperations
    filterMap:[self diagnosticReportsContents]
    predicate:predicate
    map:^ NSString * (NSString *fileName) {
      return [basePath stringByAppendingPathComponent:fileName];
    }];
}

@end

@implementation FBSimulatorSessionLogs

+ (instancetype)withSession:(FBSimulatorSession *)session;
{
  FBSimulatorSessionLogs *logs = [FBSimulatorSessionLogs new];
  logs.simulator = session.simulator;
  logs.session = session;
  return logs;
}

- (NSArray *)subprocessCrashes
{
  return [self subprocessCrashesAfterDate:self.session.history.sessionStartDate];
}

- (NSDictionary *)launchedApplicationLogs
{
  NSArray *launchedApplications = [self.session.history allLaunchedApplications];

  // TODO: Use asl(3) or syslog(1) instead of grep.
  NSMutableDictionary *logs = [NSMutableDictionary dictionary];
  for (FBProcessInfo *launchedProcess in launchedApplications) {
    logs[launchedProcess] = [[[[[FBWritableLogBuilder builder]
      updateShortName:[NSString stringWithFormat:@"log_%d", launchedProcess.processIdentifier]]
      updateFileType:@"log"]
      updatePathFromBlock:^ BOOL (NSString *path) {
        NSString *shellCommand = [NSString stringWithFormat:
          @"cat %@ | grep %d",
          [FBTaskExecutor escapePathForShell:self.systemLogPath],
          launchedProcess.processIdentifier
        ];

        return [[[[[FBTaskExecutor.sharedInstance
         withShellTaskCommand:shellCommand]
         withStdOutPath:path stdErrPath:nil]
         build]
         startSynchronouslyWithTimeout:10]
         wasSuccessful];
      }]
      build];
  }

  return [logs copy];
}

@end
