/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestProcess.h"

#import <sys/wait.h>

#import <FBControlCore/FBControlCore.h>

#import "FBXCTestConstants.h"
#import "XCTestBootstrapError.h"

static NSTimeInterval const CrashLogStartDateFuzz = -20;
static NSTimeInterval const CrashLogWaitTime = 180; // In case resources are pegged, just wait
static NSTimeInterval const SampleDuration = 1;

@implementation FBXCTestProcess

#pragma mark Public

+ (FBFuture<NSNumber *> *)ensureProcess:(id<FBLaunchedProcess>)process completesWithin:(NSTimeInterval)timeout withCrashLogDetection:(BOOL)crashLogDetection queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  // The start date of the process appear slightly older than we might think, so avoid missing it by a few seconds.
  NSDate *startDate = [NSDate.date dateByAddingTimeInterval:CrashLogStartDateFuzz];
  // This will be called right after the process has launched, so we should start listening for crash logs now.
  FBCrashLogNotifier *notifier = nil;
  if (crashLogDetection) {
    notifier = [FBCrashLogNotifier.sharedInstance startListening:YES];
  }

  [logger logFormat:@"Waiting for %d to exit within %f seconds", process.processIdentifier, timeout];
  return [[[process
    statLoc]
    onQueue:queue timeout:timeout handler:^{
      return [FBXCTestProcess performSampleStackshotOnProcessIdentifier:process.processIdentifier forTimeout:timeout queue:queue logger:logger];;
    }]
    onQueue:queue fmap:^(id _) {
      // This will not be reached if the sample error ran.
      return [[process
        exitCode] // Re-map to the exit code as the first part of the chain will fire on *any* exit (including crashes).
        onQueue:queue chain:^ FBFuture<NSNumber *> * (FBFuture<NSNumber *> *exitCodeFuture) {
          // If there's an exit code, there wasn't a crash. Exit code handling is done in the caller.
          if (exitCodeFuture.state == FBFutureStateDone) {
            return exitCodeFuture;
          }
          // Here we know a signalled exit has occurred. This return happens if no crash log detection is present.
          if (!notifier) {
            return exitCodeFuture;
          }
          // Here we know we want to find the crash log, so attempt to get it.
          return [FBXCTestProcess performCrashLogQueryForProcess:process startDate:startDate notifier:notifier crashLogWaitTime:CrashLogWaitTime queue:queue logger:logger];
        }];
    }];
}

+ (nullable NSString *)describeFailingExitCode:(int)exitCode
{
  switch (exitCode) {
    case 0:
      return nil;
    case 1:
      return nil;
    case TestShimExitCodeDLOpenError:
      return @"DLOpen Error";
    case TestShimExitCodeBundleOpenError:
      return @"Error opening test bundle";
    case TestShimExitCodeMissingExecutable:
      return @"Missing executable";
    case TestShimExitCodeXCTestFailedLoading:
      return @"XCTest Framework failed loading";
    default:
      return [NSString stringWithFormat:@"Unknown xctest exit code %d", exitCode];
  }
}

+ (FBFuture<id> *)performSampleStackshotOnProcessIdentifier:(pid_t)processIdentifier forTimeout:(NSTimeInterval)timeout queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  [logger logFormat:@"Performing stackshot on process %d as it has not exited after %f seconds", processIdentifier, timeout];
  return [[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/sample" arguments:@[@(processIdentifier).stringValue, @(SampleDuration).stringValue]]
    runUntilCompletion]
    onQueue:queue handleError:^(NSError *error) {
      return [[[FBXCTestError
        describeFormat:@"Failed to obtain a stack sample of stalled xctest process %d", processIdentifier]
        causedBy:error]
        failFuture];
    }]
    onQueue:queue fmap:^(FBTask<NSNull *, NSData *, NSData *> *task) {
      [logger logFormat:@"Stackshot completed of process %d", processIdentifier];
      return [[FBXCTestError
        describeFormat:@"Waited %f seconds for process %d to terminate, but the xctest process stalled: %@", timeout, processIdentifier, task.stdOut]
        failFuture];
    }];
}

#pragma mark Private

+ (FBFuture<id> *)performSampleStackshotOnProcess:(id<FBLaunchedProcess>)process forTimeout:(NSTimeInterval)timeout queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  return [[self
    performSampleStackshotOnProcessIdentifier:process.processIdentifier forTimeout:timeout queue:queue logger:logger]
    onQueue:queue notifyOfCompletion:^(id _) {
      [logger logFormat:@"Terminating stalled xctest process %d", process.processIdentifier];
      [process.statLoc cancel];
    }];
}

+ (FBFuture<NSNumber *> *)performCrashLogQueryForProcess:(id<FBLaunchedProcess>)process startDate:(NSDate *)startDate notifier:(FBCrashLogNotifier *)notifier crashLogWaitTime:(NSTimeInterval)crashLogWaitTime queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  [logger logFormat:@"xctest process (%d) died prematurely, checking for crash log for %f seconds", process.processIdentifier, crashLogWaitTime];
  return [[[FBXCTestProcess
    crashLogsForTerminationOfProcess:process since:startDate notifier:notifier crashLogWaitTime:crashLogWaitTime queue:queue]
    rephraseFailure:@"xctest process (%d) exited abnormally with no crash log, to check for yourself look in ~/Library/Logs/DiagnosticReports", process.processIdentifier]
    onQueue:queue fmap:^(FBCrashLogInfo *crashInfo) {
      NSString *crashString = [NSString stringWithContentsOfFile:crashInfo.crashPath encoding:NSUTF8StringEncoding error:nil];
      return [[FBXCTestError
        describeFormat:@"xctest process crashed\n %@", crashString]
        failFuture];
    }];
}

+ (FBFuture<FBCrashLogInfo *> *)crashLogsForTerminationOfProcess:(id<FBLaunchedProcess>)process since:(NSDate *)sinceDate notifier:(FBCrashLogNotifier *)notifier crashLogWaitTime:(NSTimeInterval)crashLogWaitTime queue:(dispatch_queue_t)queue
{
  NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[
    [FBCrashLogInfo predicateForCrashLogsWithProcessID:process.processIdentifier],
    [FBCrashLogInfo predicateNewerThanDate:sinceDate],
  ]];

  return [[notifier
    nextCrashLogForPredicate:predicate]
    timeout:crashLogWaitTime waitingFor:@"Crash logs for terminated process %d to appear", process.processIdentifier];
}

@end
