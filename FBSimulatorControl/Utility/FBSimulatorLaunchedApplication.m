/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorLaunchedApplication.h"

#import "FBSimulator+Private.h"
#import "FBSimulator.h"

@interface FBSimulatorLaunchedApplication ()

@property (nonatomic, strong, readonly) FBProcessFileAttachment *attachment;
@property (nonatomic, weak, nullable, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorLaunchedApplication

@synthesize applicationTerminated = _applicationTerminated;
@synthesize processIdentifier = _processIdentifier;

#pragma mark Initializers

+ (FBFuture<FBSimulatorLaunchedApplication *> *)applicationWithSimulator:(FBSimulator *)simulator configuration:(FBApplicationLaunchConfiguration *)configuration attachment:(FBProcessFileAttachment *)attachment launchFuture:(FBFuture<NSNumber *> *)launchFuture
{
  return [launchFuture
    onQueue:simulator.workQueue map:^(NSNumber *processIdentifierNumber) {
      pid_t processIdentifier = processIdentifierNumber.intValue;
      FBFuture<NSNull *> *terminationFuture = [FBSimulatorLaunchedApplication terminationFutureForSimulator:simulator processIdentifier:processIdentifier];
      FBSimulatorLaunchedApplication *operation = [[self alloc] initWithSimulator:simulator configuration:configuration attachment:attachment processIdentifier:processIdentifier terminationFuture:terminationFuture];
      return operation;
    }];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator configuration:(FBApplicationLaunchConfiguration *)configuration attachment:(FBProcessFileAttachment *)attachment processIdentifier:(pid_t)processIdentifier terminationFuture:(FBFuture<NSNull *> *)terminationFuture
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _configuration = configuration;
  _attachment = attachment;
  _processIdentifier = processIdentifier;
  _applicationTerminated = [terminationFuture
    onQueue:simulator.workQueue chain:^(FBFuture *future) {
      return [[attachment detach] chainReplace:future];
    }];
  return self;
}

#pragma mark Properties

- (NSString *)bundleID
{
  return self.configuration.bundleID;
}

- (id<FBProcessFileOutput>)stdOut
{
  return self.attachment.stdOut;
}

- (id<FBProcessFileOutput>)stdErr
{
  return self.attachment.stdErr;
}

#pragma mark Helpers

+ (FBFuture<NSNull *> *)terminationFutureForSimulator:(FBSimulator *)simulator processIdentifier:(pid_t)processIdentifier
{
  return [[[self
    processTerminationFutureNotifierForProcessIdentifier:processIdentifier]
    mapReplace:NSNull.null]
    onQueue:simulator.workQueue respondToCancellation:^{
      return [[FBProcessTerminationStrategy
        strategyWithProcessFetcher:FBProcessFetcher.new workQueue:simulator.workQueue logger:simulator.logger]
        killProcessIdentifier:processIdentifier];
    }];
}

+ (FBFuture<NSNumber *> *)processTerminationFutureNotifierForProcessIdentifier:(pid_t)processIdentifier
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbsimulatorcontrol.application_termination_notifier", DISPATCH_QUEUE_SERIAL);
  dispatch_source_t source = dispatch_source_create(
    DISPATCH_SOURCE_TYPE_PROC,
    (unsigned long) processIdentifier,
    DISPATCH_PROC_EXIT,
    queue
  );

  FBMutableFuture<NSNumber *> *future = FBMutableFuture.future;
  [future onQueue:queue respondToCancellation:^ FBFuture<NSNull *> * {
    dispatch_source_cancel(source);
    return FBFuture.empty;
  }];
  dispatch_source_set_event_handler(source, ^(){
    [future resolveWithResult:@(processIdentifier)];
    dispatch_source_cancel(source);
  });
  dispatch_resume(source);

  return future;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Application Operation %@ | pid %d | State %@", self.configuration.description, self.processIdentifier, self.applicationTerminated];
}

@end
