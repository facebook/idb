/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorDapServerCommands.h"
#import "FBSimulator.h"

@interface FBSimulatorDapServerCommand ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorDapServerCommand

#pragma mark Initializers
+ (instancetype)commandsWithTarget:(FBSimulator *)target
{
  return [[self alloc] initWithSimulator:target];
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

- (FBFuture<FBProcess<id, id<FBDataConsumer>, NSString *> *> *) launchDapServer:dapPath stdIn:(FBProcessInput *)stdIn stdOut:(id<FBDataConsumer>)stdOut{
  NSString *dap_log_dir = [self.simulator.coreSimulatorLogsDirectory stringByAppendingPathComponent:@"dap"];
  
  NSError *error = nil;
  BOOL createdDir = [[NSFileManager defaultManager] createDirectoryAtPath:dap_log_dir
                    withIntermediateDirectories:YES
                    attributes:nil
                    error:&error];
  
  if (!createdDir) {
    return [[FBControlCoreError
             describeFormat:@"Dap Command: Failed to create log director on path %@. Error: %@", dap_log_dir, error.localizedDescription]
      failFuture];
  }
  
  NSString *log_string = [dap_log_dir stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".log"]];
  BOOL createdLogFile = [[NSFileManager defaultManager] createFileAtPath:log_string
                          contents:nil
                          attributes:nil];
  if (!createdLogFile) {
    return [[FBControlCoreError
      describeFormat:@"Failed to create log file on path %@", log_string]
      failFuture];
  }
  
  [self.simulator.logger.debug logFormat:@"Dap Command: Launching dap server logging at path %@", log_string];
  NSDictionary<NSString *, NSString *> *envs = @{
    @"LLDBVSCODE_LOG": log_string
  };
  NSString *fullPath = [self.simulator.dataDirectory stringByAppendingPathComponent:dapPath];
  return [[[[[[FBProcessBuilder
              withLaunchPath:fullPath]
              withEnvironment:envs]
              withStdIn:stdIn]
              withStdOutConsumer: stdOut]
              withStdErrInMemoryAsString]
              start];
}

@end
