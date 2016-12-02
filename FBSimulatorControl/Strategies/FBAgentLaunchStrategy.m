/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBAgentLaunchStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import <CoreSimulator/SimDevice.h>

#import "FBSimulator+Helpers.h"
#import "FBSimulator+Private.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorError.h"
#import "FBSimulatorDiagnostics.h"
#import "FBSimulatorProcessFetcher.h"

@interface FBAgentLaunchStrategy ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) FBSimulatorProcessFetcher *processFetcher;

@end

@implementation FBAgentLaunchStrategy

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
  _processFetcher = simulator.processFetcher;

  return self;
}

- (nullable FBProcessInfo *)launchAgent:(FBAgentLaunchConfiguration *)agentLaunch error:(NSError **)error;
{
  FBSimulator *simulator = self.simulator;
  NSError *innerError = nil;
  FBDiagnostic *stdOutDiagnostic = nil;
  FBDiagnostic *stdErrDiagnostic = nil;
  NSFileHandle *stdOutHandle = nil;
  NSFileHandle *stdErrHandle = nil;

  BOOL connectStdout = (agentLaunch.options & FBProcessLaunchOptionsWriteStdout) == FBProcessLaunchOptionsWriteStdout;
  if (connectStdout) {
    FBDiagnosticBuilder *builder = [FBDiagnosticBuilder builderWithDiagnostic:[simulator.diagnostics stdOut:agentLaunch]];
    NSString *path = [builder createPath];

    if (![NSFileManager.defaultManager createFileAtPath:path contents:NSData.data attributes:nil]) {
      return [[FBSimulatorError
        describeFormat:@"Could not create stdout at path '%@' for config '%@'", path, agentLaunch]
        fail:error];
    }
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fileHandle) {
      return [[FBSimulatorError
        describeFormat:@"Could not file handle for stdout at path '%@' for config '%@'", path, self]
        fail:error];
    }
    stdOutDiagnostic = [[builder updatePath:path] build];
    stdOutHandle = fileHandle;
  }

  BOOL connectStderr = (agentLaunch.options & FBProcessLaunchOptionsWriteStderr) == FBProcessLaunchOptionsWriteStderr;
  if (connectStderr) {
    FBDiagnosticBuilder *builder = [FBDiagnosticBuilder builderWithDiagnostic:[simulator.diagnostics stdErr:agentLaunch]];
    NSString *path = [builder createPath];

    if (![NSFileManager.defaultManager createFileAtPath:path contents:NSData.data attributes:nil]) {
      return [[FBSimulatorError
        describeFormat:@"Could not create stdout at path '%@' for config '%@'", path, agentLaunch]
        fail:error];
    }
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fileHandle) {
      return [[FBSimulatorError
        describeFormat:@"Could not file handle for stdout at path '%@' for config '%@'", path, self]
        fail:error];
    }
    stdErrDiagnostic = [[builder updatePath:path] build];
    stdErrHandle = fileHandle;
  }

  NSDictionary *options = [agentLaunch simDeviceLaunchOptionsWithStdOut:stdOutHandle stdErr:stdErrHandle];
  if (!options) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  FBProcessInfo *process = [self
    spawnLongRunningWithPath:agentLaunch.agentBinary.path
    options:options
    terminationHandler:NULL
    error:&innerError];

  if (!process) {
    return [[[[FBSimulatorError
      describeFormat:@"Failed to start Agent %@", agentLaunch]
      causedBy:innerError]
      inSimulator:simulator]
      fail:error];
  }

  [simulator.eventSink agentDidLaunch:agentLaunch didStart:process stdOut:stdOutHandle stdErr:stdErrHandle];
  return process;
}

- (nullable NSString *)launchConsumingStdout:(FBAgentLaunchConfiguration *)agentLaunch error:(NSError **)error
{
  // Construct a pipe to stdout and read asynchronously from it.
  // Synchronize on the mutable string.
  NSPipe *stdOutPipe = [NSPipe pipe];
  NSDictionary *options = [agentLaunch simDeviceLaunchOptionsWithStdOut:stdOutPipe.fileHandleForWriting stdErr:nil];

  NSError *innerError = nil;
  pid_t processIdentifier = [[FBAgentLaunchStrategy withSimulator:self.simulator]
    spawnShortRunningWithPath:agentLaunch.agentBinary.path
    options:options
    timeout:FBControlCoreGlobalConfiguration.fastTimeout
    error:&innerError];
  if (processIdentifier <= 0) {
    return [[[FBSimulatorError
      describeFormat:@"Running %@ %@ failed", agentLaunch.agentBinary.name, [FBCollectionInformation oneLineDescriptionFromArray:agentLaunch.arguments]]
      causedBy:innerError]
      fail:error];
  }
  [stdOutPipe.fileHandleForWriting closeFile];
  NSData *data = [stdOutPipe.fileHandleForReading readDataToEndOfFile];
  NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  return [output copy];
}

#pragma mark Private

- (nullable FBProcessInfo *)spawnLongRunningWithPath:(NSString *)launchPath options:(nullable NSDictionary<NSString *, id> *)options terminationHandler:(nullable FBAgentLaunchCallback)terminationHandler error:(NSError **)error
{
  return [self processInfoForProcessIdentifier:[self.simulator.device spawnWithPath:launchPath options:options terminationHandler:terminationHandler error:error] error:error];
}

- (pid_t)spawnShortRunningWithPath:(NSString *)launchPath options:(nullable NSDictionary<NSString *, id> *)options timeout:(NSTimeInterval)timeout error:(NSError **)error
{
  __block volatile uint32_t hasTerminated = 0;
  FBAgentLaunchCallback terminationHandler = ^() {
    OSAtomicOr32Barrier(1, &hasTerminated);
  };

  pid_t processIdentifier = [self.simulator.device spawnWithPath:launchPath options:options terminationHandler:terminationHandler error:error];
  if (processIdentifier <= 0) {
    return processIdentifier;
  }

  BOOL successfulWait = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilTrue:^BOOL{
    return hasTerminated == 1;
  }];
  if (!successfulWait) {
    return [[FBSimulatorError
      describeFormat:@"Short Live process of pid %d of launch %@ with options %@ did not terminate in '%f' seconds", processIdentifier, launchPath, options, timeout]
      failBool:error];
  }

  return processIdentifier;
}

- (FBProcessInfo *)processInfoForProcessIdentifier:(pid_t)processIdentifier error:(NSError **)error
{
  if (processIdentifier <= -1) {
    return nil;
  }

  FBProcessInfo *processInfo = [self.processFetcher.processFetcher processInfoFor:processIdentifier timeout:FBControlCoreGlobalConfiguration.regularTimeout];
  if (!processInfo) {
    return [[FBSimulatorError describeFormat:@"Timed out waiting for process info for pid %d", processIdentifier] fail:error];
  }
  return processInfo;
}

@end
