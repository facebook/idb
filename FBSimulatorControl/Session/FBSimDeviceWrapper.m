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

#import "FBSimulatorError.h"

const long kFBSimDeviceCommandTimeout = 30;

@interface FBSimDeviceWrapper ()

@property (atomic, assign) SimDevice *device;

@end

@implementation FBSimDeviceWrapper

- (instancetype)initWithSimDevice:(SimDevice *)device
{
  if (!(self = [self init])) {
    return nil;
  }

  _device = device;

  return self;
}

- (BOOL)runInvocationInBackgroundUntilTimeout:(NSInvocation *)invocation
{
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

  NSInvocation *newInvocation = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(runInvocation:withSemaphore:)]];
  [newInvocation setTarget:self];
  [newInvocation setSelector:@selector(runInvocation:withSemaphore:)];
  [newInvocation setArgument:&invocation atIndex:2];
  [newInvocation setArgument:&semaphore atIndex:3];
  [NSThread detachNewThreadSelector:@selector(invoke) toTarget:newInvocation withObject:nil];

  return dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, kFBSimDeviceCommandTimeout * NSEC_PER_SEC)) == 0;
}

- (void)runInvocation:(NSInvocation *)invocation withSemaphore:(dispatch_semaphore_t)semaphore
{
  NSAssert(![NSThread isMainThread], @"Should be on a background thread");

  [invocation invoke];
  dispatch_semaphore_signal(semaphore);
}

- (int)launchApplicationWithID:(NSString *)appID options:(NSDictionary *)options error:(NSError **)error
{
  NSAssert([NSThread isMainThread], @"Must be called from the main thread.");

  NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(launchApplicationWithID:options:error:)]];
  [invocation setTarget:self.device];
  [invocation setSelector:@selector(launchApplicationWithID:options:error:)];
  [invocation setArgument:&appID atIndex:2];
  [invocation setArgument:&options atIndex:3];
  [invocation setArgument:&error atIndex:4];

  if (![self runInvocationInBackgroundUntilTimeout:invocation]) {
    [[FBSimulatorError describe:@"Timed out calling launchApplicationWithID"] fail:error];
    return 0;
  }

  pid_t pid;
  [invocation getReturnValue:&pid];
  return pid;
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
    [[FBSimulatorError describe:@"Timed out calling installApplication"] fail:error];
    return NO;
  }

  BOOL rv;
  [invocation getReturnValue:&rv];
  return rv;
}

@end
