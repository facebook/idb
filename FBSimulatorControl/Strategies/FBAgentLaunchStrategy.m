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
#import "FBProcessLaunchConfiguration+Simulator.h"
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

  if (![agentLaunch createStdOutDiagnosticForSimulator:simulator diagnosticOut:&stdOutDiagnostic error:error]) {
    return nil;
  }
  if (stdOutDiagnostic) {
    NSString *path = stdOutDiagnostic.asPath;
    stdOutHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!stdOutHandle) {
      return [[FBSimulatorError
        describeFormat:@"Could not file handle for stdout at path '%@' for config '%@'", path, self]
        fail:error];
    }
  }
  if (![agentLaunch createStdErrDiagnosticForSimulator:simulator diagnosticOut:&stdErrDiagnostic error:error]) {
    return nil;
  }
  if (stdErrDiagnostic) {
    NSString *path = stdErrDiagnostic.asPath;
    stdErrHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!stdOutHandle) {
      return [[FBSimulatorError
        describeFormat:@"Could not file handle for stderr at path '%@' for config '%@'", path, self]
        fail:error];
    }
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
  FBAccumilatingFileDataConsumer *consumer = [FBAccumilatingFileDataConsumer new];
  FBFileReader *reader = [FBFileReader readerWithFileHandle:stdOutPipe.fileHandleForReading consumer:consumer];
  NSDictionary *options = [agentLaunch simDeviceLaunchOptionsWithStdOut:stdOutPipe.fileHandleForWriting stdErr:nil];

  // Start reading the pipe
  NSError *innerError = nil;
  if (![reader startReadingWithError:&innerError]) {
    return [[[FBSimulatorError
      describeFormat:@"Could not start reading stdout of %@", agentLaunch]
      causedBy:innerError]
      fail:error];
  }

  // The Process launches and terminates synchronously
  pid_t processIdentifier = [[FBAgentLaunchStrategy withSimulator:self.simulator]
    spawnShortRunningWithPath:agentLaunch.agentBinary.path
    options:options
    timeout:FBControlCoreGlobalConfiguration.fastTimeout
    error:&innerError];

  // Stop reading the pipe
  if (![reader stopReadingWithError:&innerError]) {
    return [[[FBSimulatorError
      describeFormat:@"Could not stop reading stdout of %@", agentLaunch]
      causedBy:innerError]
      fail:error];
  }

  // Fail on non-zero pid.
  if (processIdentifier <= 0) {
    return [[[FBSimulatorError
      describeFormat:@"Running %@ %@ failed", agentLaunch.agentBinary.name, [FBCollectionInformation oneLineDescriptionFromArray:agentLaunch.arguments]]
      causedBy:innerError]
      fail:error];
  }

  return [[NSString alloc] initWithData:consumer.data encoding:NSUTF8StringEncoding];
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
