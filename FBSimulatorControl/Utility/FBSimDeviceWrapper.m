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

#import "FBProcessInfo.h"
#import "FBProcessQuery.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "NSRunLoop+SimulatorControlAdditions.h"

const long SimDeviceDefaultTimeout = 60;
const NSTimeInterval ProcessInfoAvailabilityTimeout = 15;

@interface FBSimDeviceWrapper ()

@property (nonatomic, strong, readonly) SimDevice *device;
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

  return dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, SimDeviceDefaultTimeout *NSEC_PER_SEC)) == 0;
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

  NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(launchApplicationWithID:options:error:)]];
  [invocation setTarget:self.device];
  [invocation setSelector:@selector(launchApplicationWithID:options:error:)];
  [invocation setArgument:&appID atIndex:2];
  [invocation setArgument:&options atIndex:3];
  [invocation setArgument:&error atIndex:4];

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

  NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(installApplication:withOptions:error:)]];
  [invocation setTarget:self.device];
  [invocation setSelector:@selector(installApplication:withOptions:error:)];
  [invocation setArgument:&appURL atIndex:2];
  [invocation setArgument:&options atIndex:3];
  [invocation setArgument:&error atIndex:4];

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

+ (instancetype)withSimDevice:(SimDevice *)device configuration:(FBSimulatorControlConfiguration *)configuration processQuery:(FBProcessQuery *)processQuery
{
  BOOL timeoutResiliance = (configuration.options & FBSimulatorManagementOptionsUseSimDeviceTimeoutResiliance) == FBSimulatorManagementOptionsUseSimDeviceTimeoutResiliance;
  return timeoutResiliance
    ? [[FBSimDeviceWrapper_TimeoutResiliance alloc] initWithSimDevice:device processQuery:processQuery]
    : [[FBSimDeviceWrapper alloc] initWithSimDevice:device processQuery:processQuery];
}

- (instancetype)initWithSimDevice:(SimDevice *)device processQuery:(FBProcessQuery *)query
{
  if (!(self = [self init])) {
    return nil;
  }

  _device = device;
  _query = query;

  return self;
}

#pragma mark Public

- (FBProcessInfo *)launchApplicationWithID:(NSString *)appID options:(NSDictionary *)options error:(NSError **)error
{
  return [self processInfoForProcessIdentifier:[self.device launchApplicationWithID:appID options:options error:error] error:error];
}

- (BOOL)installApplication:(NSURL *)appURL withOptions:(NSDictionary *)options error:(NSError **)error
{
  return [self.device installApplication:appURL withOptions:options error:error];
}

- (FBProcessInfo *)spawnWithPath:(NSString *)launchPath options:(NSDictionary *)options terminationHandler:(id)terminationHandler error:(NSError **)error
{
  return [self processInfoForProcessIdentifier:[self.device spawnWithPath:launchPath options:options terminationHandler:terminationHandler error:error] error:error];
}

#pragma mark Private

- (FBProcessInfo *)processInfoForProcessIdentifier:(pid_t)processIdentifier error:(NSError **)error
{
  if (processIdentifier <= -1) {
    return nil;
  }

  FBProcessInfo *processInfo = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:ProcessInfoAvailabilityTimeout untilExists:^ FBProcessInfo * {
    return [self.query processInfoFor:processIdentifier];
  }];
  if (!processInfo) {
    return [[FBSimulatorError describeFormat:@"Timed out waiting for process info for pid %d", processIdentifier] fail:error];
  }
  return processInfo;
}

@end
