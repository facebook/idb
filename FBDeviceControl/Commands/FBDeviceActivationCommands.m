/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceActivationCommands.h"

#import "FBDevice.h"
#import "FBAMDServiceConnection.h"

@interface FBDeviceActivationCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;

@end

@implementation FBDeviceActivationCommands

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

#pragma mark FBDeviceActivationCommands Implementation

- (FBFuture<NSNull *> *)activate
{
  id<FBControlCoreLogger> logger = self.device.logger;
  return [[self
    activationState]
    onQueue:self.device.asyncQueue fmap:^ FBFuture<NSNull *> * (FBDeviceActivationState activationState) {
      if ([activationState isEqualToString:FBDeviceActivationStateActivated]) {
        [logger logFormat:@"Device is already activated, nothing to activate"];
        return FBFuture.empty;
      }
      if ([activationState isEqualToString:FBDeviceActivationStateUnactivated]) {
        [logger logFormat:@"Device is not activated, starting activation"];
        return [self performActivation];
      }
      return [[FBControlCoreError
        describeFormat:@"%@ is not a valid activation state", activationState]
        failFuture];
    }];
}

#pragma mark Private

- (FBFuture<NSNull *> *)confirmActivationState:(FBDeviceActivationState)activationState
{
  return [[self
    activationState]
    onQueue:self.device.asyncQueue fmap:^ FBFuture<NSNull *> * (FBDeviceActivationState actualActivationState) {
      if (![activationState isEqualToString:actualActivationState]) {
        return [[FBControlCoreError
          describeFormat:@"Activation State %@ is not equal to actual activation state %@", activationState, actualActivationState]
          failFuture];
      }
      return FBFuture.empty;
    }];
}

- (FBFuture<NSNull *> *)performActivation
{
  id<FBControlCoreLogger> logger = self.device.logger;
  return [[[[[self
    confirmActivationState:FBDeviceActivationStateUnactivated]
    onQueue:self.device.workQueue fmap:^(id _) {
      [logger logFormat:@"Building DRM Handshake Payload"];
      return [self buildDRMHandshakePayload];
    }]
    onQueue:self.device.workQueue fmap:^(NSData *drmHandhakePayload) {
      [logger logFormat:@"Obtaining Activation record from DRM Handshake Payload"];
      return [self activationRecordFromDRMHandshakePayload:drmHandhakePayload];
    }]
    onQueue:self.device.workQueue fmap:^(NSData *activationRecordPayload) {
      [logger logFormat:@"Obtaining Activation record from DRM Handshake Payload"];
      return [self activateFromActivationRecord:activationRecordPayload];
    }]
    onQueue:self.device.workQueue fmap:^(id _) {
      [logger logFormat:@"Confirming activation state is Activated"];
      return [self confirmActivationState:FBDeviceActivationStateActivated];
    }];
}

- (FBFutureContext<FBAMDServiceConnection *> *)mobileActivationService
{
  return [self.device startService:@"com.apple.mobileactivationd"];
}

- (FBFuture<FBDeviceActivationState> *)activationState
{
  return [[self
    mobileActivationService]
    onQueue:self.device.workQueue pop:^ FBFuture<NSData *> * (FBAMDServiceConnection *connection) {
      NSError *error = nil;
      id response = [connection sendAndReceiveMessage:@{@"Command": @"GetActivationStateRequest"} error:&error];
      if (!response) {
        return [FBFuture futureWithError:error];
      }
      NSString *activationState = response[@"Value"];
      if (![activationState isKindOfClass:NSString.class]) {
        return [[FBControlCoreError
          describeFormat:@"No Activation State in %@", response]
          failFuture];
      }
      return [FBFuture futureWithResult:FBDeviceActivationStateCoerceFromString(activationState)];
    }];
}

- (FBFuture<NSData *> *)buildDRMHandshakePayload
{
  return [[self
    mobileActivationService]
    onQueue:self.device.workQueue pop:^ FBFuture<NSData *> * (FBAMDServiceConnection *connection) {
      NSError *error = nil;
      id response = [connection sendAndReceiveMessage:@{@"Command": @"CreateTunnel1SessionInfoRequest"} error:&error];
      if (!response) {
        return [FBFuture futureWithError:error];
      }
      id responsePayload = response[@"Value"];
      if (!responsePayload) {
        return [[FBControlCoreError
          describeFormat:@"No 'Value' in %@", response]
          failFuture];
      }
      return [FBDeviceActivationCommands mobileActivationRequestForRequestPayload:responsePayload queue:self.device.workQueue];
    }];
}

- (FBFuture<NSData *> *)activationRecordFromDRMHandshakePayload:(NSData *)handshakePayload
{
  return [[self
    mobileActivationService]
    onQueue:self.device.workQueue pop:^ FBFuture<NSData *> * (FBAMDServiceConnection *connection) {
      NSError *error = nil;
      id response = [connection sendAndReceiveMessage:@{@"Command": @"CreateTunnel1ActivationInfoRequest", @"Value": handshakePayload} error:&error];
      if (!response) {
        return [FBFuture futureWithError:error];
      }
      NSDictionary<NSString *, id> *responsePayload = response[@"Value"];
      if (!responsePayload) {
        return [[FBControlCoreError
          describeFormat:@"No 'Value' in %@", response]
          failFuture];
      }
      return [FBDeviceActivationCommands mobileActivationActivateForRequestPayload:responsePayload queue:self.device.workQueue];
    }];
}

- (FBFuture<NSNull *> *)activateFromActivationRecord:(NSData *)activationRecord
{
  return [[self
    mobileActivationService]
    onQueue:self.device.workQueue pop:^ FBFuture<NSNull *> * (FBAMDServiceConnection *connection) {
      NSError *error = nil;
      id response = [connection sendAndReceiveMessage:@{@"Command": @"HandleActivationInfoWithSessionRequest", @"Value": activationRecord} error:&error];
      if (!response) {
        return [FBFuture futureWithError:error];
      }
      return FBFuture.empty;
    }];
}

+ (FBFuture<NSData *> *)mobileActivationRequestForRequestPayload:(NSDictionary<NSString *, id> *)requestPayload queue:(dispatch_queue_t)queue
{
  NSError *error = nil;
  NSData *body = [NSPropertyListSerialization dataWithPropertyList:requestPayload format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
  if (!body) {
    return [FBFuture futureWithError:error];
  }

  NSURL *url = [NSURL URLWithString:@"https://albert.apple.com/deviceservices/drmHandshake"];
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  request.HTTPMethod = @"POST";
  request.HTTPBody = body;
  [request setValue:@"application/x-apple-plist" forHTTPHeaderField:@"Content-Type"];
  [request setValue:@"application/xml" forHTTPHeaderField:@"Accept"];
  [request setValue:@"idb (https://github.com/facebook/idb/blob/master/FBDeviceControl/Commands/FBDeviceActivationCommands.m)" forHTTPHeaderField:@"User-Agent"];

  return [[self
    responseForRequest:request]
    onQueue:queue fmap:^(NSArray<id> *result) {
      NSHTTPURLResponse *httpResponse = result[0];
      if (httpResponse.statusCode != 200) {
        return [[FBControlCoreError
          describeFormat:@"%@ no 200", httpResponse]
          failFuture];
      }
      NSData *responseData = result[1];
      NSError *innerError = nil;
      NSDictionary<NSString *, id> *response = [NSPropertyListSerialization propertyListWithData:responseData options:0 format:nil error:&innerError];
      if (!response) {
        return [FBFuture futureWithError:innerError];
      }
      return [FBFuture futureWithResult:responseData];
    }];
}

+ (FBFuture<NSData *> *)mobileActivationActivateForRequestPayload:(NSDictionary<NSString *, id> *)requestPayload queue:(dispatch_queue_t)queue
{
  NSError *error = nil;
  NSData *payloadData = [NSPropertyListSerialization dataWithPropertyList:requestPayload format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
  if (!payloadData) {
    return [FBFuture futureWithError:error];
  }

  // Multipart info
  NSString *boundaryConstant = NSUUID.UUID.UUIDString;
  NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundaryConstant];

  NSURL *url = [NSURL URLWithString:@"https://albert.apple.com/deviceservices/deviceActivation"];
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  request.HTTPMethod = @"POST";
  request.HTTPBody = [self multipartDataFromRequestPayload:payloadData key:@"activation-info" boundary:boundaryConstant];
  [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
  [request setValue:@"idb (https://github.com/facebook/idb/blob/master/FBDeviceControl/Commands/FBDeviceActivationCommands.m)" forHTTPHeaderField:@"User-Agent"];

  return [[self
    responseForRequest:request]
    onQueue:queue fmap:^(NSArray<id> *result) {
      NSHTTPURLResponse *httpResponse = result[0];
      if (httpResponse.statusCode != 200) {
        return [[FBControlCoreError
          describeFormat:@"%@ no 200", httpResponse]
          failFuture];
      }
      NSData *responseData = result[1];
      NSError *innerError = nil;
      id response = [NSPropertyListSerialization propertyListWithData:responseData options:0 format:nil error:&innerError];
      if (!response) {
        return [FBFuture futureWithError:innerError];
      }
      id activationRecord = response[@"ActivationRecord"];
      if (!activationRecord) {
        return [[FBControlCoreError
          describeFormat:@"No 'ActivationRecord' in %@", activationRecord]
          failFuture];
      }
      NSData *activationRecordData = [NSPropertyListSerialization dataWithPropertyList:activationRecord format:NSPropertyListXMLFormat_v1_0 options:0 error:&innerError];
      if (!activationRecordData) {
        return [FBFuture futureWithError:innerError];
      }
      return [FBFuture futureWithResult:activationRecordData];
    }];
}

+ (FBFuture<id> *)responseForRequest:(NSURLRequest *)request
{
  NSURLSession *session = NSURLSession.sharedSession;
  FBMutableFuture<id> *future = FBMutableFuture.future;
  NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *responseData, NSURLResponse *response, NSError *error) {
    if (error) {
      [future resolveWithError:error];
    }
    [future resolveWithResult:@[response, responseData]];
  }];
  [task resume];
  return future;
}

+ (NSData *)multipartDataFromRequestPayload:(NSData *)payload key:(NSString *)key boundary:(NSString *)boundary
{
  NSData *dashesData = [@"--" dataUsingEncoding:NSUTF8StringEncoding];
  NSData *newlineData = [@"\r\n" dataUsingEncoding:NSUTF8StringEncoding];
  NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
  NSData *boundaryData = [boundary dataUsingEncoding:NSUTF8StringEncoding];
  NSData *valueHeaderData = [@"Content-Disposition: form-data; name=" dataUsingEncoding:NSUTF8StringEncoding];

  NSMutableData *data = NSMutableData.data;

  // Header prefixed with dashes.
  [data appendData:dashesData];
  [data appendData:boundaryData];
  [data appendData:newlineData];

  // Then the key-value
  [data appendData:valueHeaderData];
  [data appendData:keyData];
  [data appendData:newlineData];
  [data appendData:newlineData];
  [data appendData:payload];
  [data appendData:newlineData];

  // Then the trailer, suffixed with dashes
  [data appendData:dashesData];
  [data appendData:boundaryData];
  [data appendData:dashesData];
  [data appendData:newlineData];

  return data;
}

@end
