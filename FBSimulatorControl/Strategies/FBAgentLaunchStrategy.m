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

#import "FBSimulator+Helpers.h"
#import "FBProcessLaunchConfiguration+Helpers.h"
#import "FBSimDeviceWrapper.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorError.h"
#import "FBSimulatorDiagnostics.h"
#import "FBSimulatorApplication.h"
#import "FBProcessLaunchConfiguration.h"

@interface FBAgentLaunchStrategy ()

@property (nonnull, nonatomic, strong, readonly) FBSimulator *simulator;

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

  FBProcessInfo *process = [simulator.simDeviceWrapper
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

@end
