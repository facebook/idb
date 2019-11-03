/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceApplicationProcess.h"

#import "FBDevice.h"
#import "FBGDBClient.h"

@interface FBDeviceApplicationProcess ()

@property (nonatomic, weak, nullable, readonly) FBDevice *device;
@property (nonatomic, retain, readonly) FBGDBClient *gdbClient;

@end

@implementation FBDeviceApplicationProcess

@synthesize processIdentifier = _processIdentifier;

+ (FBFuture<FBDeviceApplicationProcess *> *)processWithDevice:(FBDevice *)device configuration:(FBApplicationLaunchConfiguration *)configuration gdbClient:(FBGDBClient *)gdbClient stdOut:(id<FBProcessOutput>)stdOut stdErr:(id<FBProcessOutput>)stdErr launchFuture:(FBFuture<NSNumber *> *)launchFuture
{
  return [[FBFuture
    futureWithFutures:@[
      [stdOut providedThroughConsumer],
      [stdErr providedThroughConsumer],
    ]]
    onQueue:device.workQueue fmap:^(NSArray<id<FBDataConsumer>> *consumers) {
      return [launchFuture
        onQueue:device.workQueue fmap:^(NSNumber *processIdentifier) {
          return [[gdbClient
            consumeStdOut:consumers[0] stdErr:consumers[1]]
            onQueue:device.workQueue map:^(id _) {
              return [[self alloc] initWithDevice:device gdbClient:gdbClient processIdentifier:processIdentifier.intValue];
            }];
        }];
    }];
}

- (instancetype)initWithDevice:(FBDevice *)device gdbClient:(FBGDBClient *)gdbClient processIdentifier:(pid_t)processIdentifier
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _gdbClient = gdbClient;
  _processIdentifier = processIdentifier;

  return self;
}

#pragma mark FBLaunchedProcess

- (FBFuture<NSNumber *> *)exitCode
{
  return self.gdbClient.exitCode;
}

@end
