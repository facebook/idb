/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceLinkClient.h"

#import "FBDeviceControlError.h"
#import "FBAMDServiceConnection.h"
#import "FBServiceConnectionClient.h"

// This client is based off DeviceLink.framework
// The protocol here is quite simple:
// 1) Any packet has a device-endian 32-bit unsigned integer that encodes the length of a packet. This is used for both the sending and recieving side.
// 2) The data after this is a binary-plist of the payload itself.
// 3) There is no trailer for a packet, the header defines when the end of the packet is.
// 4) Before anything starts, there's a version exchange. This uses plists as well, but the arguments are an NSArray of plist data instead of an NSDictionary.
// 5) For the message-passing usage, all messages are embedded in an NSArray with DLMessageProcessMessage, this is also the case with the response.

typedef uint HeaderIntType;

static NSUInteger HeaderLength = sizeof(HeaderIntType);

static NSData *lengthPayload(NSData *payload)
{
  HeaderIntType length = (HeaderIntType) payload.length;
  HeaderIntType lengthWire = EndianU32_NtoB(length); // The native length should be converted to big-endian (ARM).
  return [[NSData alloc] initWithBytes:&lengthWire length:HeaderLength];
}

static NSUInteger (^HeaderSizeRead)(NSData *data) = ^(NSData *responseLengthData) {
  HeaderIntType length = 0;
  [responseLengthData getBytes:&length length:HeaderLength];
  length = EndianU32_BtoN(length); // Devices are ARM (big-endian) so we need to convert it to the native endianness.
  return (NSUInteger) length;
};

static FBFuture<NSArray<id> *> * (^ParsePlistResponse)(NSData *) = ^(NSData *data) {
  NSError *error = nil;
  id response = [NSPropertyListSerialization propertyListWithData:data options:0 format:0 error:&error];
  if (!response) {
    return [FBFuture futureWithError:error];
  }
  return [FBFuture futureWithResult:response];
};


@interface FBDeviceLinkClient ()

@property (nonatomic, strong, readonly) FBServiceConnectionClient *client;

@end

@implementation FBDeviceLinkClient

#pragma mark Initializers

+ (FBFuture<FBDeviceLinkClient *> *)deviceLinkClientWithServiceConnectionClient:(FBServiceConnectionClient *)client
{
  FBDeviceLinkClient *plistClient = [[self alloc] initWithServiceConnectionClient:client];
  return [[plistClient
    performVersionExchange]
    mapReplace:plistClient];
}

- (instancetype)initWithServiceConnectionClient:(FBServiceConnectionClient *)client
{
  self = [self init];
  if (!self) {
    return nil;
  }

  _client = client;

  return self;
}

#pragma mark Public Methods

- (FBFuture<NSDictionary<id, id> *> *)processMessage:(NSArray<id> *)message
{
  return [[self
    sendAndRecieve:@[
      @"DLMessageProcessMessage",
      message,
    ]]
    onQueue:self.client.queue fmap:^(NSArray<id> *result) {
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

- (FBFuture<NSNumber *> *)performVersionExchange
{
  __block NSNumber *version = nil;
  return [[[[self.client.buffer
    consumeHeaderLength:HeaderLength derivedLength:HeaderSizeRead]
    onQueue:self.client.queue fmap:ParsePlistResponse]
    onQueue:self.client.queue fmap:^ FBFuture<NSArray<id> *> * (NSArray<id> *handshake) {
      version = handshake[1]; // Handshake packet is (DLMessageVersionExchange, MAX_VERSION_INT, MIN_VERSION_INT)
      if (![version isKindOfClass:NSNumber.class]) {
        return [[FBDeviceControlError
          describeFormat:@"%@ is not a NSNumber for the handshake version", version]
          failFuture];
      }
      NSArray<id> *response = @[
        @"DLMessageVersionExchange",
        @"DLVersionsOk",
        version,
      ];
      return [self sendAndRecieve:response];
    }]
    onQueue:self.client.queue fmap:^ FBFuture<NSNumber *> * (NSArray<id> *handshake) {
      NSString *message = handshake.firstObject;
      if (![message isEqual:DeviceReady]) {
        return [[FBDeviceControlError
          describeFormat:@"%@ is not equal to %@", message, DeviceReady]
          failFuture];
      }
      return [FBFuture futureWithResult:version];
    }];
}

- (FBFuture<NSNull *> *)sendPlist:(NSArray<id> *)payload
{
  NSError *error = nil;
  NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:payload format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
  if (!plistData) {
    return [FBFuture futureWithError:error];
  }
  [self.client sendRaw:lengthPayload(plistData)];
  [self.client sendRaw:plistData];
  return FBFuture.empty;
}

- (FBFuture<NSArray<id> *> *)sendAndRecieve:(NSArray<id> *)payload
{
  return [[[self
    sendPlist:payload]
    onQueue:self.client.queue fmap:^(id _) {
      return [self.client.buffer consumeHeaderLength:HeaderLength derivedLength:HeaderSizeRead];
    }]
    onQueue:self.client.queue fmap:ParsePlistResponse];
}

@end
