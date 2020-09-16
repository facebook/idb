/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDevicePowerCommands.h"

#import "FBDevice.h"
#import "FBAMDServiceConnection.h"

@interface FBDevicePowerCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;

@end

@implementation FBDevicePowerCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBDevice *)target
{
  return [[self alloc] initWithDevice:target];
}

- (instancetype)initWithDevice:(FBDevice *)device
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;

  return self;
}

#pragma mark FBPowerCommands Implementation

- (FBFuture<NSNull *> *)shutdown
{
  return [self sendRelayCommand:@"Shutdown"];
}

- (FBFuture<NSNull *> *)reboot
{
  return [self sendRelayCommand:@"Restart"];
}

#pragma mark Private

- (FBFuture<NSNull *> *)sendRelayCommand:(NSString *)request
{
  return [[self.device
    startService:@"com.apple.mobile.diagnostics_relay"]
    onQueue:self.device.workQueue pop:^ FBFuture<NSNull *> * (FBAMDServiceConnection *connection) {
      NSError *error = nil;
      NSDictionary<NSString *, id> *result = [connection sendAndReceiveMessage:@{@"Request": request} error:&error];
      if (!result) {
        return [FBFuture futureWithError:error];
      }
      if (![result[@"Status"] isEqualToString:@"Success"]) {
        return [[FBControlCoreError
          describeFormat:@"Not successful %@", result]
          failFuture];
      }
      return FBFuture.empty;
    }];
}

@end
