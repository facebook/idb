/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimDeviceWrapper.h"

#import <CoreSimulator/SimDevice.h>

#import <FBControlCore/FBControlCore.h>

#import <libkern/OSAtomic.h>

#import "FBSimulator+Helpers.h"
#import "FBSimulator.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorProcessFetcher.h"

@interface FBSimDeviceWrapper ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) FBSimulatorProcessFetcher *processFetcher;

- (FBProcessInfo *)processInfoForProcessIdentifier:(pid_t)processIdentifier error:(NSError **)error;

@end

@implementation FBSimDeviceWrapper

#pragma mark Initializers

+ (instancetype)withSimulator:(FBSimulator *)simulator processFetcher:(FBSimulatorProcessFetcher *)processFetcher
{
  return [[FBSimDeviceWrapper alloc] initWithSimulator:simulator processFetcher:processFetcher];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator processFetcher:(FBSimulatorProcessFetcher *)processFetcher
{
  if (!(self = [self init])) {
    return nil;
  }

  _simulator = simulator;
  _processFetcher = processFetcher;

  return self;
}

#pragma mark Public

- (BOOL)installApplication:(NSURL *)appURL withOptions:(NSDictionary *)options error:(NSError **)error
{
  // Calling -[SimDevice installApplication:withOptions:error:] will result in the Application unexpectedly terminating.
  return [self.simulator.device installApplication:appURL withOptions:options error:error];
}

- (BOOL)uninstallApplication:(NSString *)bundleID withOptions:(NSDictionary *)options error:(NSError **)error
{
  // The options don't appear to do much, simctl itself doesn't use them.
  return [self.simulator.device uninstallApplication:bundleID withOptions:nil error:error];
}

- (FBProcessInfo *)spawnLongRunningWithPath:(NSString *)launchPath options:(NSDictionary *)options terminationHandler:(FBSimDeviceWrapperCallback)terminationHandler error:(NSError **)error
{
  return [self processInfoForProcessIdentifier:[self.simulator.device spawnWithPath:launchPath options:options terminationHandler:terminationHandler error:error] error:error];
}

- (pid_t)spawnShortRunningWithPath:(NSString *)launchPath options:(NSDictionary *)options timeout:(NSTimeInterval)timeout error:(NSError **)error
{
  __block volatile uint32_t hasTerminated = 0;
  FBSimDeviceWrapperCallback terminationHandler = ^() {
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

#pragma mark Private

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
