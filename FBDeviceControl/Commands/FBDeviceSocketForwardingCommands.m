/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceSocketForwardingCommands.h"

#import "FBDevice.h"
#import "FBDeviceControlError.h"

@interface FBDeviceSocketForwardingCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;

@end

@implementation FBDeviceSocketForwardingCommands

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

#pragma mark FBSocketForwardingCommands Implementation

- (FBFuture<NSNull *> *)drainLocalFileInput:(int)localFileDescriptorInput localFileOutput:(int)localFileDescriptorOutput remotePort:(int)remotePort
{
  NSError *error = nil;
  id<FBDataConsumer> localConsumer = [FBFileWriter asyncWriterWithFileDescriptor:localFileDescriptorOutput closeOnEndOfFile:NO error:&error];
  if (!localConsumer) {
    return [FBFuture futureWithError:error];
  }
  return [[self
    consumerForRemotePort:remotePort writingTo:localConsumer]
    onQueue:self.device.asyncQueue pop:^(id<FBDataConsumer> remoteConsumer) {
      id<FBFileReader> reader = [FBFileReader readerWithFileDescriptor:localFileDescriptorInput closeOnEndOfFile:NO consumer:remoteConsumer logger:nil];
      return [[reader
        startReading]
        onQueue:self.device.asyncQueue fmap:^(id _) {
          return reader.finishedReading;
        }];
    }];
}

#pragma mark Private

- (FBFutureContext<id<FBDataConsumer>> *)consumerForRemotePort:(int)remotePort writingTo:(id<FBDataConsumer>)consumer
{
  return [[self
    localSocketFromRemotePort:remotePort]
    onQueue:self.device.asyncQueue pend:^(NSNumber *remoteSocket) {
      NSError *error = nil;
      id<FBDataConsumer> writer = [FBFileWriter asyncWriterWithFileDescriptor:remoteSocket.intValue closeOnEndOfFile:NO error:&error];
      if (!writer) {
        return [FBFuture futureWithError:error];
      }
      id<FBFileReader> reader = [FBFileReader readerWithFileDescriptor:remoteSocket.intValue closeOnEndOfFile:NO consumer:consumer logger:nil];
      return [[reader
        startReading]
        mapReplace:writer];
    }];
}

- (FBFutureContext<NSNumber *> *)localSocketFromRemotePort:(int)remotePort
{
  id<FBControlCoreLogger> logger = self.device.logger;
  return [[[self.device
    connectToDeviceWithPurpose:@"Socket Connection"]
    onQueue:self.device.workQueue pop:^(id<FBDeviceCommands> device) {
      int connectionID = device.calls.GetConnectionID(device.amDeviceRef);
      if (connectionID <= 0) {
        return [[FBDeviceControlError
          describeFormat:@"Failed to get ConnectionID from Device"]
          failFuture];
      }
      [logger logFormat:@"Got connection ID %d, for device. Connecting to remote port %d", connectionID, remotePort];
      int localSocket = 0;
      int status = device.calls.USBMuxConnectByPort(connectionID, htons(remotePort), &localSocket);
      if (status != 0) {
        return [[FBDeviceControlError
          describeFormat:@"Failed to connect to remote port %d", remotePort]
          failFuture];
      }
      [logger logFormat:@"Got local socket %d for remote port %d", localSocket, remotePort];
      return [FBFuture futureWithResult:@(localSocket)];
    }]
    onQueue:self.device.asyncQueue contextualTeardown:^(NSNumber *localSocketNumber, FBFutureState _) {
      [logger logFormat:@"Closing local socket %@", localSocketNumber];
      close(localSocketNumber.intValue);
      return FBFuture.empty;
    }];
}

@end
