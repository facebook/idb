/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceLinkClient.h"

#import "FBDeviceControlError.h"
#import "FBAMDServiceConnection.h"

// This client is based off DeviceLink.framework, which is a bidirectional messaging system on a protocol that's used in multiple places.
// The protocol that this client uses is a standard "Plist Interchange" format that's used by a number of lockdown services.
// It's implemented in the AMDServiceConnectionSendMessage/AMDServiceConnectionReceiveMessage calls, but can also be implemented manually.
// The protocol is as follows:
// 1) Any packet has a device-endian 32-bit unsigned integer that encodes the length of a packet. This is used for both the sending and recieving side.
// 2) The data after this is a binary-plist of the payload itself.
// 3) There is no trailer for a packet, the header defines when the end of the packet is.
// 4) Before anything starts, there's a version exchange. This uses plists as well, but the arguments are an NSArray of plist data instead of an NSDictionary.
// 5) For the message-passing usage, all messages are embedded in an NSArray with DLMessageProcessMessage, this is also the case with the response.

@interface FBDeviceLinkClient ()

@property (nonatomic, strong, readonly) FBAMDServiceConnection *connection;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBDeviceLinkClient

#pragma mark Initializers

+ (FBFuture<FBDeviceLinkClient *> *)deviceLinkClientWithConnection:(FBAMDServiceConnection *)connection
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbdevicecontrol.fbdevicelinkclient", DISPATCH_QUEUE_SERIAL);
  FBDeviceLinkClient *plistClient = [[self alloc] initWithServiceConnection:connection queue:queue];
  return [[plistClient
    performVersionExchange]
    mapReplace:plistClient];
}

- (instancetype)initWithServiceConnection:(FBAMDServiceConnection *)connection queue:(dispatch_queue_t)queue
{
  self = [self init];
  if (!self) {
    return nil;
  }

  _connection = connection;
  _queue = queue;

  return self;
}

#pragma mark Public Methods

- (FBFuture<NSDictionary<id, id> *> *)processMessage:(NSArray<id> *)message
{
  return [[self
    sendAndReceivePlist:@[
      @"DLMessageProcessMessage",
      message,
    ]]
    onQueue:self.queue fmap:^(NSArray<id> *result) {
      NSDictionary<NSString *, id> *response = result[1];
      if (![response isKindOfClass:NSDictionary.class]) {
        return [[FBDeviceControlError
          describeFormat:@"%@ is not a NSDictionary", response]
          failFuture];
      }
      return [FBFuture futureWithResult:response];
    }];
}

#pragma mark Private

static NSString *const DeviceReady = @"DLMessageDeviceReady";

- (FBFuture<NSNull *> *)performVersionExchange
{
  return [[[self
    receivePlist]
    onQueue:self.queue fmap:^ FBFuture<id> * (id plist) {
      if (![plist isKindOfClass:NSArray.class]) {
        return [[FBDeviceControlError
          describeFormat:@"%@ is not an array in version exchange", plist]
          failFuture];
      }
      NSNumber *versionNumber = plist[1];
      if (![versionNumber isKindOfClass:NSNumber.class]) {
        return [[FBDeviceControlError
          describeFormat:@"%@ is not a NSNumber for the handshake version", versionNumber]
          failFuture];
      }
      NSArray<id> *response = @[
        @"DLMessageVersionExchange",
        @"DLVersionsOk",
        versionNumber,
      ];
      return [self sendAndReceivePlist:response];
    }]
    onQueue:self.queue fmap:^(id plist) {
      if (![plist isKindOfClass:NSArray.class]) {
        return [[FBDeviceControlError
          describeFormat:@"%@ is not an array in version exchange", plist]
          failFuture];
      }
      NSString *message = plist[0];
      if (![message isKindOfClass:NSString.class]) {
        return [[FBDeviceControlError
          describeFormat:@"%@ is not a NSString for the device ready call", message]
          failFuture];
      }
      if (![message isEqualToString:DeviceReady]) {
        return [[FBDeviceControlError
          describeFormat:@"%@ is not equal to %@", message, DeviceReady]
          failFuture];
      }
      return [FBFuture futureWithResult:NSNull.null];
    }];
}

- (FBFuture<NSNull *> *)sendPlist:(id)payload
{
  return [FBFuture
    onQueue:self.queue resolveValue:^ NSNull * (NSError **error) {
      if (![self.connection sendMessage:payload error:error]) {
        return nil;
      }
      return NSNull.null;
    }];
}

- (FBFuture<id> *)receivePlist
{
  return [FBFuture
    onQueue:self.queue resolveValue:^ id (NSError **error) {
      return [self.connection receiveMessageWithError:error];
    }];
}

- (FBFuture<id> *)sendAndReceivePlist:(id)payload
{
  return [[self
    sendPlist:payload]
    onQueue:self.queue fmap:^(id _) {
      return [self receivePlist];
    }];
}

@end
