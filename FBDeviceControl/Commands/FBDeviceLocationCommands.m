/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceLocationCommands.h"

#import "FBDevice.h"
#import "FBDevice+Private.h"
#import "FBDeviceControlError.h"
#import "FBAMDServiceConnection.h"
#import "FBAFCConnection.h"

@interface FBDeviceLocationCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;

@end

@implementation FBDeviceLocationCommands

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

#pragma mark FBDeviceLocationCommands

static const int StartCommand = 0x0000000;

- (FBFuture<NSNull *> *)overrideLocationWithLongitude:(double)longitude latitude:(double)latitude
{
  return [[[self.device
    mountDeveloperDiskImage]
    onQueue:self.device.workQueue pushTeardown:^(id _) {
      return [self.device startService:@"com.apple.dt.simulatelocation"];
    }]
    onQueue:self.device.workQueue pop:^ FBFuture<NSNull *> * (FBAMDServiceConnection *connection) {
      NSData *start = [[NSData alloc] initWithBytes:&StartCommand length:sizeof(StartCommand)];
      NSError *error = nil;
      id<FBAMDServiceConnectionTransfer> transfer = connection.serviceConnectionWrapped;
      if (![transfer send:start error:&error]) {
        return [FBFuture futureWithError:error];
      }
      NSString *value = [NSString stringWithFormat:@"%f", latitude];
      NSData *data = [[NSData alloc] initWithBytes:value.UTF8String length:strlen(value.UTF8String)];
      if (![transfer sendWithLengthHeader:data error:&error]) {
        return [FBFuture futureWithError:error];
      }
      value = [NSString stringWithFormat:@"%f", longitude];
      data = [[NSData alloc] initWithBytes:value.UTF8String length:strlen(value.UTF8String)];
      if (![transfer sendWithLengthHeader:data error:&error]) {
        return [FBFuture futureWithError:error];
      }
      return FBFuture.empty;
    }];
}

@end
