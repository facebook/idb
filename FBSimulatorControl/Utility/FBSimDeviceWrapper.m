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

#import "FBAddVideoPolyfill.h"
#import "FBProcessInfo.h"
#import "FBProcessQuery+Helpers.h"
#import "FBProcessQuery.h"
#import "FBSimulator.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorControlGlobalConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorLogger.h"
#import "NSRunLoop+SimulatorControlAdditions.h"

@interface FBSimDeviceWrapper ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) FBProcessQuery *query;

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

  int64_t timeout = ((int64_t) FBSimulatorControlGlobalConfiguration.slowTimeout) * ((int64_t) NSEC_PER_SEC);
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

  NSError *__autoreleasing innerError = nil;
  NSError *__autoreleasing *innerErrorPointer = &innerError;
  NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(launchApplicationWithID:options:error:)]];
  [invocation setTarget:self.simulator.device];
  [invocation setSelector:@selector(launchApplicationWithID:options:error:)];
  [invocation setArgument:&appID atIndex:2];
  [invocation setArgument:&options atIndex:3];
  [invocation setArgument:&innerErrorPointer atIndex:4];
  error = innerErrorPointer;
  if (![self runInvocationInBackgroundUntilTimeout:invocation]) {
    return [[FBSimulatorError describe:@"Timed out calling launchApplicationWithID"] fail:error];
  }

  pid_t pid;
  [invocation getReturnValue:&pid];
  return [self processInfoForProcessIdentifier:pid error:error];
}

- (BOOL)installApplication:(NSURL *)appURL withOptions:(NSDictionary *)options error:(NSError **)error
{
  NSAssert([NSThread isMainThread], @"Must be called from the main thread.");

  NSError *__autoreleasing innerError = nil;
  NSError *__autoreleasing *innerErrorPointer = &innerError;
  NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(installApplication:withOptions:error:)]];
  [invocation setTarget:self.simulator.device];
  [invocation setSelector:@selector(installApplication:withOptions:error:)];
  [invocation setArgument:&appURL atIndex:2];
  [invocation setArgument:&options atIndex:3];
  [invocation setArgument:&innerErrorPointer atIndex:4];
  error = innerErrorPointer;
  if (![self runInvocationInBackgroundUntilTimeout:invocation]) {
    return [[FBSimulatorError describe:@"Timed out calling installApplication"] failBool:error];
  }

  BOOL rv;
  [invocation getReturnValue:&rv];
  return rv;
}

@end

@implementation FBSimDeviceWrapper

#pragma mark Initializers

+ (instancetype)withSimulator:(FBSimulator *)simulator configuration:(FBSimulatorControlConfiguration *)configuration processQuery:(FBProcessQuery *)processQuery
{
  BOOL timeoutResiliance = (configuration.options & FBSimulatorManagementOptionsUseSimDeviceTimeoutResiliance) == FBSimulatorManagementOptionsUseSimDeviceTimeoutResiliance;
  return timeoutResiliance
    ? [[FBSimDeviceWrapper_TimeoutResiliance alloc] initWithSimulator:simulator processQuery:processQuery]
    : [[FBSimDeviceWrapper alloc] initWithSimulator:simulator processQuery:processQuery];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator processQuery:(FBProcessQuery *)query
{
  if (!(self = [self init])) {
    return nil;
  }

  _simulator = simulator;
  _query = query;

  return self;
}

#pragma mark Public

- (BOOL)shutdownWithError:(NSError **)error
{
  FBSimulator *simulator = self.simulator;
  id<FBSimulatorLogger> logger = self.simulator.logger;
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
    [logger.debug logFormat:@"Shutdown of %@ succeeded as it is allready shutdown", simulator.udid];
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

- (FBProcessInfo *)launchApplicationWithID:(NSString *)appID options:(NSDictionary *)options error:(NSError **)error
{
  return [self processInfoForProcessIdentifier:[self.simulator.device launchApplicationWithID:appID options:options error:error] error:error];
}

- (BOOL)installApplication:(NSURL *)appURL withOptions:(NSDictionary *)options error:(NSError **)error
{
  return [self.simulator.device installApplication:appURL withOptions:options error:error];
}

- (FBProcessInfo *)spawnWithPath:(NSString *)launchPath options:(NSDictionary *)options terminationHandler:(id)terminationHandler error:(NSError **)error
{
  return [self processInfoForProcessIdentifier:[self.simulator.device spawnWithPath:launchPath options:options terminationHandler:terminationHandler error:error] error:error];
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

  FBProcessInfo *processInfo = [self.query processInfoFor:processIdentifier timeout:FBSimulatorControlGlobalConfiguration.regularTimeout];
  if (!processInfo) {
    return [[FBSimulatorError describeFormat:@"Timed out waiting for process info for pid %d", processIdentifier] fail:error];
  }
  return processInfo;
}

@end
