/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceRecoveryCommands.h"

#import "FBDevice.h"
#import "FBDeviceCommands.h"
#import "FBDeviceControlError.h"

@interface FBDeviceRecoveryCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;

@end

@implementation FBDeviceRecoveryCommands

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

#pragma mark FBDeviceRecoveryCommands Implementation

- (FBFuture<NSNull *> *)enterRecovery
{
  return [[self.device
    connectToDeviceWithPurpose:@"enter_recovery"]
    onQueue:self.device.workQueue pop:^ FBFuture<NSNull *> * (id<FBDeviceCommands> device) {
      int status = device.calls.EnterRecovery(device.amDeviceRef);
      if (status != 0) {
        NSString *internalMessage = CFBridgingRelease(device.calls.CopyErrorText(status));
        return [[FBDeviceControlError
          describeFormat:@"Failed have device enter recovery %@", internalMessage]
          failFuture];
      }
      return FBFuture.empty;
    }];
}

@end
