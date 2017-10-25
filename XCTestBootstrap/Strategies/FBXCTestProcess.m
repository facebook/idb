/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestProcess.h"

#import <sys/wait.h>

#import <FBControlCore/FBControlCore.h>

#import "XCTestBootstrapError.h"
#import "FBXCTestProcessExecutor.h"

static NSTimeInterval const CrashLogStartDateFuzz = -10;

@interface FBXCTestProcess ()

@property (nonatomic, strong, readonly) id<FBXCTestProcessExecutor> executor;

@end

@implementation FBXCTestProcess

#pragma mark Initializers

+ (instancetype)processWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOutReader:(id<FBFileConsumer>)stdOutReader stdErrReader:(id<FBFileConsumer>)stdErrReader executor:(id<FBXCTestProcessExecutor>)executor
{
  return [[FBXCTestProcess alloc] initWithLaunchPath:launchPath arguments:arguments environment:environment waitForDebugger:waitForDebugger stdOutReader:stdOutReader stdErrReader:stdErrReader executor:executor];
}

- (instancetype)initWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOutReader:(id<FBFileConsumer>)stdOutReader stdErrReader:(id<FBFileConsumer>)stdErrReader executor:(id<FBXCTestProcessExecutor>)executor
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _launchPath = launchPath;
  _arguments = arguments;
  _environment = environment;
  _waitForDebugger = waitForDebugger;
  _stdOutReader = stdOutReader;
  _stdErrReader = stdErrReader;
  _executor = executor;

  return self;
}

#pragma mark Public

- (FBFuture<NSNumber *> *)start:(pid_t *)processIdentifierOut timeout:(NSTimeInterval)timeout
{
  // Construct and launch the task.
  NSDate *startDate = [NSDate.date dateByAddingTimeInterval:CrashLogStartDateFuzz];
  pid_t processIdentifier = 0;

  FBFuture<NSNull *> *base = [[self.executor
    startProcess:self processIdentifierOut:&processIdentifier]
    onQueue:self.executor.workQueue fmap:^(FBXCTestProcessInfo *result) {
      NSError *exitError = [FBXCTestProcess abnormalExitErrorFor:result.processIdentifier exitCode:result.exitCode startDate:startDate];
      if (exitError) {
        return [FBFuture futureWithError:exitError];
      }
      return [FBFuture futureWithResult:@(result.processIdentifier)];
    }];
  FBFuture<NSNumber *> *timeoutFuture = [FBXCTestProcess timeoutFuture:timeout queue:self.executor.workQueue processIdentifier:processIdentifier];

  if (processIdentifierOut) {
    *processIdentifierOut = processIdentifier;
  }
  return [FBFuture race:@[base, timeoutFuture]];
}

#pragma mark Private

+ (FBFuture<NSNumber *> *)timeoutFuture:(NSTimeInterval)timeout queue:(dispatch_queue_t)queue processIdentifier:(pid_t)processIdentifier
{
  return [[FBFuture
    futureWithDelay:timeout future:[FBFuture futureWithResult:NSNull.null]]
    onQueue:queue fmap:^(id _) {
      NSError *error = [FBXCTestProcess timeoutErrorWithTimeout:timeout processIdentifier:processIdentifier];
      return [FBFuture futureWithError:error];
    }];
}

+ (NSError *)timeoutErrorWithTimeout:(NSTimeInterval)timeout processIdentifier:(pid_t)processIdentifier
{
  // If the xctest process has stalled, we should sample it (if possible), then terminate it.
  NSString *sample = [FBXCTestProcess sampleStalledProcess:processIdentifier];
  return [[FBXCTestError
    describeFormat:@"Waited %f seconds for process %d to terminate, but the xctest process stalled: %@", timeout, processIdentifier, sample]
    build];
}

+ (NSError *)abnormalExitErrorFor:(pid_t)processIdentifier exitCode:(int)exitCode startDate:(NSDate *)startDate
{
  // If exited abnormally, check for a crash log
  if (exitCode == 0 || exitCode == 1) {
    return nil;
  }
  FBCrashLogInfo *crashLogInfo = [FBXCTestProcess crashLogsForChildProcessOf:processIdentifier since:startDate];
  if (crashLogInfo) {
    FBDiagnostic *diagnosticCrash = [crashLogInfo toDiagnostic:FBDiagnosticBuilder.builder];
    return [[FBXCTestError
      describeFormat:@"xctest process crashed\n %@", diagnosticCrash.asString]
      build];
  }
  return [[FBXCTestError
    describeFormat:@"xctest process exited abnormally with exit code %d", exitCode]
    build];
}

+ (nullable FBCrashLogInfo *)crashLogsForChildProcessOf:(pid_t)processIdentifier since:(NSDate *)sinceDate
{
  NSSet<NSNumber *> *possiblePPIDs = [NSSet setWithArray:@[
    @(processIdentifier),
    @(NSProcessInfo.processInfo.processIdentifier),
  ]];

  NSPredicate *crashLogInfoPredicate = [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *crashLogInfo, id _) {
    return [possiblePPIDs containsObject:@(crashLogInfo.parentProcessIdentifier)];
  }];
  return [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout untilExists:^ FBCrashLogInfo * {
    return [[[FBCrashLogInfo
      crashInfoAfterDate:sinceDate]
      filteredArrayUsingPredicate:crashLogInfoPredicate]
      firstObject];
  }];
}

+ (nullable NSString *)sampleStalledProcess:(pid_t)processIdentifier
{
  return [[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/sample" arguments:@[@(processIdentifier).stringValue, @"1"]]
    build]
    startSynchronouslyWithTimeout:5]
    stdOut];
}

@end
