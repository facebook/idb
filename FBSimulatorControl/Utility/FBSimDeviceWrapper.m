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

#import "FBAddVideoPolyfill.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"

@interface FBSimDeviceWrapper ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) FBProcessFetcher *processFetcher;

- (FBProcessInfo *)processInfoForProcessIdentifier:(pid_t)processIdentifier error:(NSError **)error;

@end

@interface FBSimDeviceWrapper_TimeoutResiliance : FBSimDeviceWrapper

@end

@implementation FBSimDeviceWrapper_TimeoutResiliance

- (BOOL)runInvocationInBackgroundUntilTimeout:(NSInvocation *)invocation
{
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

  NSInvocation *newInvocation = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(runInvocation:withSemaphore:)]];
  [newInvocation setTarget:self];
  [newInvocation setSelector:@selector(runInvocation:withSemaphore:)];
  [newInvocation setArgument:&invocation atIndex:2];
  [newInvocation setArgument:&semaphore atIndex:3];
  [NSThread detachNewThreadSelector:@selector(invoke) toTarget:newInvocation withObject:nil];

  int64_t timeout = ((int64_t) FBControlCoreGlobalConfiguration.slowTimeout) * ((int64_t) NSEC_PER_SEC);
  return dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, timeout)) == 0;
}

- (void)runInvocation:(NSInvocation *)invocation withSemaphore:(dispatch_semaphore_t)semaphore
{
  NSAssert(![NSThread isMainThread], @"Should be on a background thread");

  [invocation invoke];
  dispatch_semaphore_signal(semaphore);
}

- (FBProcessInfo *)launchApplicationWithID:(NSString *)appID options:(NSDictionary *)options error:(NSError **)error
{
  NSAssert([NSThread isMainThread], @"Must be called from the main thread.");

  NSError *innerError = nil;
  NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(launchApplicationWithID:options:error:)]];
  [invocation setTarget:self.simulator.device];
  [invocation setSelector:@selector(launchApplicationWithID:options:error:)];
  [invocation setArgument:&appID atIndex:2];
  [invocation setArgument:&options atIndex:3];
  [invocation setArgument:&innerError atIndex:4];
  if (![self runInvocationInBackgroundUntilTimeout:invocation]) {
    return [[FBSimulatorError describe:@"Timed out calling launchApplicationWithID"] fail:error];
  }

  pid_t pid;
  [invocation getReturnValue:&pid];
  if (pid <= 0) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  return [self processInfoForProcessIdentifier:pid error:error];
}

- (BOOL)installApplication:(NSURL *)appURL withOptions:(NSDictionary *)options error:(NSError **)error
{
  NSAssert([NSThread isMainThread], @"Must be called from the main thread.");

  NSError *innerError = nil;
  NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(installApplication:withOptions:error:)]];
  [invocation setTarget:self.simulator.device];
  [invocation setSelector:@selector(installApplication:withOptions:error:)];
  [invocation setArgument:&appURL atIndex:2];
  [invocation setArgument:&options atIndex:3];
  [invocation setArgument:&innerError atIndex:4];
  if (![self runInvocationInBackgroundUntilTimeout:invocation]) {
    return [[FBSimulatorError describe:@"Timed out calling installApplication"] failBool:error];
  }

  BOOL returnValue;
  [invocation getReturnValue:&returnValue];
  if (!returnValue) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }
  return YES;
}

@end

@implementation FBSimDeviceWrapper

#pragma mark Initializers

+ (instancetype)withSimulator:(FBSimulator *)simulator configuration:(FBSimulatorControlConfiguration *)configuration processFetcher:(FBProcessFetcher *)processFetcher
{
  BOOL timeoutResiliance = (configuration.options & FBSimulatorManagementOptionsUseSimDeviceTimeoutResiliance) == FBSimulatorManagementOptionsUseSimDeviceTimeoutResiliance;
  return timeoutResiliance
    ? [[FBSimDeviceWrapper_TimeoutResiliance alloc] initWithSimulator:simulator processFetcher:processFetcher]
    : [[FBSimDeviceWrapper alloc] initWithSimulator:simulator processFetcher:processFetcher];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator processFetcher:(FBProcessFetcher *)processFetcher
{
  if (!(self = [self init])) {
    return nil;
  }

  _simulator = simulator;
  _processFetcher = processFetcher;

  return self;
}

#pragma mark Public

- (BOOL)shutdownWithError:(NSError **)error
{
  FBSimulator *simulator = self.simulator;
  id<FBControlCoreLogger> logger = self.simulator.logger;
  [logger.debug logFormat:@"Starting Safe Shutdown of %@", simulator.udid];

  // If the device is in a strange state, we should bail now
  if (simulator.state == FBSimulatorStateUnknown) {
    return [[[[FBSimulatorError
      describe:@"Failed to prepare simulator for usage as it is in an unknown state"]
      inSimulator:simulator]
      logger:logger]
      failBool:error];
  }

  // Calling shutdown when already shutdown should be avoided (if detected).
  if (simulator.state == FBSimulatorStateShutdown) {
    [logger.debug logFormat:@"Shutdown of %@ succeeded as it is already shutdown", simulator.udid];
    return YES;
  }

  // Xcode 7 has a 'Creating' step that we should wait on before confirming the simulator is ready.
  // It is possible to recover from this with a few tricks.
  NSError *innerError = nil;
  if (simulator.state == FBSimulatorStateCreating) {

    [logger.debug logFormat:@"Simulator %@ is Creating, waiting for state to change to Shutdown", simulator.udid];
    if (![simulator waitOnState:FBSimulatorStateShutdown withError:&innerError]) {

      [logger.debug logFormat:@"Simulator %@ is stuck in Creating: erasing now", simulator.udid];
      if (![simulator eraseWithError:&innerError]) {
        return [[[[[FBSimulatorError
          describe:@"Failed trying to prepare simulator for usage by erasing a stuck 'Creating' simulator %@"]
          causedBy:innerError]
          inSimulator:simulator]
          logger:logger]
          failBool:error];
      }

      // If a device has been erased, we should wait for it to actually be shutdown. Ff it can't be, fail
      if (![simulator waitOnState:FBSimulatorStateShutdown withError:&innerError]) {
        return [[[[[FBSimulatorError
          describe:@"Failed trying to wait for a 'Creating' simulator to be shutdown after being erased"]
          causedBy:innerError]
          inSimulator:simulator]
          logger:logger]
          failBool:error];
      }
    }

    [logger.debug logFormat:@"Simulator %@ has transitioned from Creating to Shutdown", simulator.udid];
    return YES;
  }

  // Code 159 (Xcode 7) or 146 (Xcode 6) is 'Unable to shutdown device in current state: Shutdown'
  // We can safely ignore these codes and then confirm that the simulator is truly shutdown.
  [logger.debug logFormat:@"Shutting down Simulator %@", simulator.udid];
  if (![simulator.device shutdownWithError:&innerError] && innerError.code != 159 && innerError.code != 146) {
    return [[[[[FBSimulatorError
      describe:@"Simulator could not be shutdown"]
      causedBy:innerError]
      inSimulator:simulator]
      logger:logger]
      failBool:error];
  }

  [logger.debug logFormat:@"Confirming Simulator %@ is shutdown", simulator.udid];
  if (![simulator waitOnState:FBSimulatorStateShutdown withError:&innerError]) {
    return [[[[[FBSimulatorError
      describe:@"Failed to wait for simulator preparation to shutdown device"]
      causedBy:innerError]
      inSimulator:simulator]
      logger:logger]
      failBool:error];
  }
  [logger.debug logFormat:@"Simulator %@ is now shutdown", simulator.udid];
  return YES;
}

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

- (BOOL)addVideos:(NSArray *)paths error:(NSError **)error
{
  if ([self.simulator.device respondsToSelector:@selector(addVideo:error:)]) {
    for (NSString *path in paths) {
      NSURL *url = [NSURL fileURLWithPath:path];
      NSError *innerError = nil;
      if (![self.simulator.device addVideo:url error:&innerError]) {
        return [[[FBSimulatorError
          describeFormat:@"Failed to upload video at path %@", path]
          causedBy:innerError]
          failBool:error];
      }
    }
    return YES;
  }
  return [[FBAddVideoPolyfill withSimulator:self.simulator] addVideos:paths error:error];
}

#pragma mark Private

- (FBProcessInfo *)processInfoForProcessIdentifier:(pid_t)processIdentifier error:(NSError **)error
{
  if (processIdentifier <= -1) {
    return nil;
  }

  FBProcessInfo *processInfo = [self.processFetcher processInfoFor:processIdentifier timeout:FBControlCoreGlobalConfiguration.regularTimeout];
  if (!processInfo) {
    return [[FBSimulatorError describeFormat:@"Timed out waiting for process info for pid %d", processIdentifier] fail:error];
  }
  return processInfo;
}

@end
