/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceLinkClient.h"

#import "FBDeviceControlError.h"
#import "FBAMDServiceConnection.h"

// This client is based off DeviceLink.framework, which is a bidirectional messaging system on top of the "plist messaging" protocol documented in FBAMDServiceConnection.h.
// The "DeviceLink" protocol is as follows
// 1) Before anything starts, there's a version exchange. The device sends an initial packet contains a version number for the DeviceLink protocol. This is an NSArray of plist data (not an NSDictionary)
// 2) The host then acknowledges that it can proceed by sending an "ok" message, including the version number from #1
// 3) The host can then send requests in the "plist messaging" format and the device responds back.

@interface FBDeviceLinkClient ()

@property (nonatomic, strong, readonly) FBAMDServiceConnection *connection;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBDeviceLinkClient

#pragma mark Initializers

+ (FBFuture<FBDeviceLinkClient *> *)deviceLinkClientWithConnection:(FBAMDServiceConnection *)connection
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbdevicecontrol.fbdevicelinkclient", DISPATCH_QUEUE_SERIAL);
  return [[FBDeviceLinkClient
    performVersionExchange:connection queue:queue]
    onQueue:queue map:^(id _) {
      return [[self alloc] initWithServiceConnection:connection queue:queue];
    }];
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

static NSString *const ProcessMessage = @"DLMessageProcessMessage";

- (FBFuture<NSDictionary<NSString *, id> *> *)processMessage:(id)message
{
  FBAMDServiceConnection *connection = self.connection;
  return [FBFuture
    onQueue:self.queue resolveValue:^ NSDictionary<NSString *, id> * (NSError **error) {
      NSArray<id> *result = [connection sendAndReceiveMessage:@[ProcessMessage, message] error:error];
      if (!result) {
        return nil;
      }
      NSString *responseType = result[0];
      if (![responseType isKindOfClass:NSString.class]) {
        return [[FBDeviceControlError
          describeFormat:@"%@ is not an NSString in %@", responseType, result]
          fail:error];
      }
      if (![responseType isEqualToString:ProcessMessage]) {
        return [[FBDeviceControlError
          describeFormat:@"%@ should be a %@", responseType, ProcessMessage]
          fail:error];
      }
      NSDictionary<NSString *, id> *response = result[1];
      if (![response isKindOfClass:NSDictionary.class]) {
        return [[FBDeviceControlError
          describeFormat:@"%@ is not a NSDictionary", response]
          fail:error];
      }
      return response;
    }];
}

#pragma mark Private

static NSString *const DeviceReady = @"DLMessageDeviceReady";

+ (FBFuture<NSNull *> *)performVersionExchange:(FBAMDServiceConnection *)connection queue:(dispatch_queue_t)queue
{
  return [FBFuture
    onQueue:queue resolveValue:^ NSNull * (NSError **error) {
      id plist = [connection receiveMessageWithError:error];
      if (![plist isKindOfClass:NSArray.class]) {
        return [[FBDeviceControlError
          describeFormat:@"%@ is not an array in version exchange", plist]
          fail:error];
      }
      NSNumber *versionNumber = plist[1];
      if (![versionNumber isKindOfClass:NSNumber.class]) {
        return [[FBDeviceControlError
          describeFormat:@"%@ is not a NSNumber for the handshake version", versionNumber]
          fail:error];
      }
      NSArray<id> *response = @[
        @"DLMessageVersionExchange",
        @"DLVersionsOk",
        versionNumber,
      ];
      plist = [connection sendAndReceiveMessage:response error:error];
      if (!plist) {
        return nil;
      }
      if (![plist isKindOfClass:NSArray.class]) {
        return [[FBDeviceControlError
          describeFormat:@"%@ is not an array in version exchange", plist]
          fail:error];
      }
      NSString *message = plist[0];
      if (![message isKindOfClass:NSString.class]) {
        return [[FBDeviceControlError
          describeFormat:@"%@ is not a NSString for the device ready call", message]
          fail:error];
      }
      if (![message isEqualToString:DeviceReady]) {
        return [[FBDeviceControlError
          describeFormat:@"%@ is not equal to %@", message, DeviceReady]
          fail:error];
      }
      return NSNull.null;
    }];
}

@end
