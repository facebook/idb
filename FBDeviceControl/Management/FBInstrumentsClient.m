/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBInstrumentsClient.h"

#import "FBAMDServiceConnection.h"

#pragma mark DTX Internals

/**
 Understanding of the DTXMessage protocol is informed by the [ios_instruments_client project](https://github.com/troybowman/ios_instruments_client)
 */
typedef struct
{
  uint32 magic;
  uint32 cb;
  uint16 fragmentId;
  uint16 fragmentCount;
  uint32 length;
  uint32 identifier;
  uint32 conversationIndex;
  uint32 channelCode;
  uint32 expectsReply;
} DTXMessageHeader;

typedef struct
{
  uint32 flags;
  uint32 auxiliaryLength;
  uint64 totalLength;
} DTXMessagePayloadHeader;

#pragma mark Object Internals

typedef struct {
  BOOL success;
  uint32 messageIdentifier;
  uint32 channelCode;
  id returnValue;
  NSArray<id> *auxillaryValues;
} ResponsePayload;

typedef struct {
  NSString *selector;
  NSArray<NSData *> *argumentsData;
  uint32 messageIdentifier;
  uint32 channelCode;
  BOOL expectsReply;
} RequestPayload;

static const ResponsePayload InvalidResponsePayload = {
  .success = NO,
  .messageIdentifier = 0,
  .channelCode = 0,
  .returnValue = nil,
  .auxillaryValues = nil,
};

@interface FBInstrumentsClient ()

@property (nonatomic, assign, readwrite) uint32 lastMessageIdentifier;
@property (nonatomic, assign, readwrite) int32_t lastChannelIdentifier;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *channels;
@property (nonatomic, strong, readonly) FBAMDServiceConnection *connection;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBInstrumentsClient

#pragma mark Initializers

+ (FBFuture<FBInstrumentsClient *> *)instrumentsClientWithServiceConnection:(FBAMDServiceConnection *)connection logger:(id<FBControlCoreLogger>)logger
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbdevicecontrol.fbinstrumentsclient", DISPATCH_QUEUE_SERIAL);
  return [FBFuture
    onQueue:queue resolveValue:^ FBInstrumentsClient * (NSError **error) {
      uint32 responseMessageIdentifier = 0;
      NSDictionary<NSString *, id> *channels = [FBInstrumentsClient getAvailableChannels:connection responseMessageIdentifierOut:&responseMessageIdentifier error:error];
      if (!channels) {
        return nil;
      }
      return [[self alloc] initWithConnection:connection channels:channels lastMessageIdentifier:responseMessageIdentifier queue:queue logger:logger];
    }];
}

- (instancetype)initWithConnection:(FBAMDServiceConnection *)connection channels:(NSDictionary<NSString *, id> *)channels lastMessageIdentifier:(uint32)lastMessageIdentifier queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _connection = connection;
  _channels = channels;
  _queue = queue;
  _logger = logger;
  _lastMessageIdentifier = lastMessageIdentifier;
  _lastChannelIdentifier = 0;

  return self;
}

#pragma mark Public Methods

static NSString *const DeviceInfoChannel = @"com.apple.instruments.server.services.deviceinfo";

- (FBFuture<NSDictionary<NSString *, NSNumber *> *> *)runningApplications
{
  return [FBFuture
    onQueue:self.queue resolveValue:^ NSDictionary<NSString *, NSNumber *> * (NSError **error) {
      ResponsePayload response = [self onChannelIdentifier:DeviceInfoChannel performSelector:@"runningProcesses" argumentsData:nil error:error];
      if (response.success == NO) {
        return nil;
      }
      NSMutableDictionary<NSString *, NSNumber *> *nameToPid = NSMutableDictionary.dictionary;
      for (NSDictionary<NSString *, id> *process in response.returnValue) {
        BOOL isApplication = [process[@"isApplication"] boolValue];
        if (isApplication == NO) {
          continue;
        }
        NSNumber *pid = process[@"pid"];
        NSString *processName = process[@"name"];
        nameToPid[processName] = pid;
      }
      return nameToPid;
    }];
}

static NSString *const ProcessControlChannel = @"com.apple.instruments.server.services.processcontrol";

- (FBFuture<NSNumber *> *)launchApplication:(FBApplicationLaunchConfiguration *)configuration
{
  return [FBFuture
    onQueue:self.queue resolveValue:^ NSNumber * (NSError **error) {
      NSDictionary<NSString *, NSNumber *> *options = @{
        @"StartSuspendedKey": @(configuration.waitForDebugger),
        @"KillExisting": @(configuration.launchMode != FBApplicationLaunchModeFailIfRunning),
      };
      ResponsePayload response = [self
        onChannelIdentifier:ProcessControlChannel
        performSelector:@"launchSuspendedProcessWithDevicePath:bundleIdentifier:environment:arguments:options:"
        argumentsData:@[
          [FBInstrumentsClient argumentDataForArgument:@""], // devicePath:
          [FBInstrumentsClient argumentDataForArgument:configuration.bundleID], // bundleIdentifier:
          [FBInstrumentsClient argumentDataForArgument:configuration.environment], // environment:
          [FBInstrumentsClient argumentDataForArgument:configuration.arguments], // arguments:
          [FBInstrumentsClient argumentDataForArgument:options], // options:
        ]
        error:error];
      if (response.success == NO) {
        return nil;
      }
      return response.returnValue;
    }];
}

- (FBFuture<NSNull *> *)killProcess:(pid_t)processIdentifier
{
  return [FBFuture
    onQueue:self.queue resolveValue:^ NSNull * (NSError **error) {
      ResponsePayload response = [self
        onChannelIdentifier:ProcessControlChannel
        performSelector:@"killPid:"
        argumentsData:@[
          [FBInstrumentsClient argumentDataForArgument:@(processIdentifier)], // pid:
        ]
        error:error];
      if (response.success == NO) {
        return nil;
      }
      return NSNull.null;
    }];
}

#pragma mark Private Class Methods

+ (NSData *)capabilitiesArgumentData
{
  static dispatch_once_t onceToken;
  static NSData *data;
  dispatch_once(&onceToken, ^{
     data = [self argumentDataForArgument:@{@"com.apple.private.DTXBlockCompression": @2, @"com.apple.private.DTXConnection": @1}];
  });
  return data;
}

+ (NSSet<Class> *)supportedReturnSerializerValues
{
  static dispatch_once_t onceToken;
  static NSSet<Class> *classes;
  dispatch_once(&onceToken, ^{
     classes = [NSSet setWithArray:@[NSString.class, NSNumber.class, NSDate.class, NSError.class, NSData.class, NSDictionary.class, NSArray.class]];
  });
  return classes;
}

+ (NSDictionary<NSString *, id> *)getAvailableChannels:(FBAMDServiceConnection *)connection responseMessageIdentifierOut:(uint32 *)responseMessageIdentifierOut error:(NSError **)error
{
  RequestPayload request = {
    .selector = @"_notifyOfPublishedCapabilities:",
    .argumentsData = @[self.capabilitiesArgumentData],
    .messageIdentifier = 1,
    .channelCode = 0,
    .expectsReply = NO,
  };
  const ResponsePayload response = [self onConnection:connection requestSendAndReceive:request error:error];
  if (response.success == NO) {
    return nil;
  }
  NSDictionary<NSString *, NSNumber *> *channels = response.auxillaryValues.firstObject;
  if (![channels isKindOfClass:NSDictionary.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a dictionary", channels]
      fail:error];
  }
  return channels;
}

+ (ResponsePayload)onConnection:(FBAMDServiceConnection *)connection requestSendAndReceive:(RequestPayload)request error:(NSError **)error
{
  // The Service Connection wrapping is mandatory in iOS 14 and above, since secure transports are necessary.
  // For pre-iOS 14 raw transfer is sufficient, but using the Service Connection is still fine as this will not apply encryption on the transport.
  id<FBAMDServiceConnectionTransfer> transfer = connection.serviceConnectionWrapped;
  NSData *requestData = [self requestDataFromRequest:request];
  if (![transfer send:requestData error:error]) {
    return InvalidResponsePayload;
  }
  return [self recieveMessage:transfer request:request error:error];
}

static const uint32 DTXMessageHeaderMagic = 0x1F3D5B79;

+ (NSData *)requestDataFromRequest:(RequestPayload)request
{
  // Arguments are serialized into the auxillary data.
  NSData *auxillaryData = [self auxillaryDataFromArgumentsData:request.argumentsData];

  // The selector is the "return value" of a request. In a response this will be the return value of the remote method.
  NSError *error = nil;
  NSData *selectorData = [NSKeyedArchiver archivedDataWithRootObject:request.selector requiringSecureCoding:NO error:&error];
  NSAssert(selectorData, @"%@", error);

  // Message header is derivable from payload sizing.
  DTXMessagePayloadHeader payloadHeader;
  payloadHeader.flags = 0x2 | (request.expectsReply ? 0x1000 : 0);
  payloadHeader.auxiliaryLength = (uint32) auxillaryData.length;
  payloadHeader.totalLength = auxillaryData.length + selectorData.length;

  // All messages have a magic number.
  DTXMessageHeader messageHeader;
  messageHeader.magic = DTXMessageHeaderMagic;
  messageHeader.cb = sizeof(DTXMessageHeader);
  // We're sending data in a single fragment.
  messageHeader.fragmentId = 0;
  messageHeader.fragmentCount = 1;
  messageHeader.length = (uint32) sizeof(payloadHeader) + (uint32) payloadHeader.totalLength;
  messageHeader.identifier = request.messageIdentifier;
  messageHeader.conversationIndex = 0;
  messageHeader.channelCode = request.channelCode;
  messageHeader.expectsReply = (request.expectsReply ? 1 : 0);

  // Construct the payload from the slices of data.
  // This is not a multi-part message so is:
  // 1) The message header, containing the total length of the entire payload.
  // 2) The payload header, containing sizing for the aux and selector/return payloads.
  // 3) The aux data (arguments to the remote call).
  // 4) The selector/return payload (the selector to perform on the remote object).
  NSMutableData *data = NSMutableData.data;
  [data appendBytes:&messageHeader length:sizeof(messageHeader)];
  [data appendBytes:&payloadHeader length:sizeof(payloadHeader)];
  [data appendData:auxillaryData];
  [data appendData:selectorData];
  return data;
}

static const uint64 ArgumentMagic = 0x1F0;
static const uint32 EmptyDictionaryKey = 10;
static const uint32 ObjectArgumentType = 2;
static const uint32 Int32ArgumentType = 3;

+ (NSData *)auxillaryDataFromArgumentsData:(nullable NSArray<NSData *> *)arguments
{
  if (arguments == nil) {
    return NSData.data;
  }
  NSMutableData *argumentsData = NSMutableData.data;
  for (NSData *argument in arguments) {
    [argumentsData appendData:argument];
  }
  uint64 payloadLength = argumentsData.length;
  NSMutableData *data = NSMutableData.data;
  [data appendBytes:&ArgumentMagic length:sizeof(ArgumentMagic)];
  [data appendBytes:&payloadLength length:sizeof(payloadLength)];
  [data appendData:argumentsData];
  return data;
}

+ (NSData *)argumentDataForArgument:(id)argument
{
  NSError *error = nil;
  NSData *argumentData = [NSKeyedArchiver archivedDataWithRootObject:argument requiringSecureCoding:NO error:&error];
  NSAssert(argumentData, @"%@", error);
  uint32 argumentSize = (uint32) argumentData.length;
  NSMutableData *data = NSMutableData.data;
  [data appendBytes:&EmptyDictionaryKey length:sizeof(EmptyDictionaryKey)];
  [data appendBytes:&ObjectArgumentType length:sizeof(ObjectArgumentType)];
  [data appendBytes:&argumentSize length:sizeof(argumentSize)];
  [data appendData:argumentData];
  return data;
}

+ (NSData *)argumentDataForInt32:(int32_t)value
{
  NSMutableData *data = NSMutableData.data;
  [data appendBytes:&EmptyDictionaryKey length:sizeof(EmptyDictionaryKey)];
  [data appendBytes:&Int32ArgumentType length:sizeof(ObjectArgumentType)];
  [data appendBytes:&value length:sizeof(value)];
  return data;
}

+ (NSArray<id> *)objectArgumentsFromAuxillaryData:(NSData *)data error:(NSError **)error
{
  if (data.length < 16) {
    return [[FBControlCoreError
      describeFormat:@"Data is of insufficient length %@", data]
      fail:error];
  }
  uint64 magic = 0;
  data = [self advanceData:data buffer:&magic length:sizeof(magic)];
  uint64 payloadLength = 0;
  data = [self advanceData:data buffer:&payloadLength length:sizeof(payloadLength)];

  // We need at least the length of the length of the argument data within the buffer.
  NSMutableArray<id> *arguments = NSMutableArray.array;
  while (data.length > (sizeof(uint32) * 3)) {
    uint32 dictionaryKey = 0;
    uint32 argumentType = 0;
    uint32 argumentLength = 0;
    data = [self advanceData:data buffer:&dictionaryKey length:sizeof(dictionaryKey)];
    data = [self advanceData:data buffer:&argumentType length:sizeof(argumentType)];
    if (argumentType != 2) {
      return [[FBControlCoreError
        describeFormat:@"Canot decode argument of type %d", argumentType]
        fail:error];
    }
    data = [self advanceData:data buffer:&argumentLength length:sizeof(argumentLength)];
    NSData *argumentData = nil;
    data = [self advanceData:data dataOut:&argumentData length:argumentLength];
    id argument = [NSKeyedUnarchiver unarchivedObjectOfClasses:self.supportedReturnSerializerValues fromData:argumentData error:error];
    if (!argument) {
      return [[FBControlCoreError
        describeFormat:@"Failed to decode argument %@", data]
        fail:error];
    }
    [arguments addObject:argument];
  }
  return arguments;
}

+ (NSData *)advanceData:(NSData *)data buffer:(void *)buffer length:(size_t)length
{
  [data getBytes:buffer length:length];
  return [data subdataWithRange:NSMakeRange(length, data.length - length)];
}

+ (NSData *)advanceData:(NSData *)data dataOut:(NSData **)dataOut length:(size_t)length
{
  if (dataOut) {
    *dataOut = [data subdataWithRange:NSMakeRange(0, length)];
  }
  return [data subdataWithRange:NSMakeRange(length, data.length - length)];
}

+ (ResponsePayload)recieveMessage:(id<FBAMDServiceConnectionTransfer>)transfer request:(RequestPayload)request error:(NSError **)error
{
  // This header will start the first iteration of the loop, then is overwritten on each iteration.
  DTXMessageHeader messageHeader = {
    .magic = 0,
    .cb = 0,
    .fragmentId = 0,
    .fragmentCount = UINT16_MAX,
    .length = 0,
    .identifier = 0,
    .conversationIndex = 0,
    .channelCode = 0,
    .expectsReply = 0,
  };
  NSMutableData *payloadData = NSMutableData.data;

  // Will execute at least once, exiting when there are no more fragments.
  while (messageHeader.fragmentId < messageHeader.fragmentCount - 1) {
    // Obtain the header payload in this iteration.
    if (![transfer receive:&messageHeader ofSize:sizeof(messageHeader) error:error]) {
      return InvalidResponsePayload;
    }
    // The data is corrupted in some way if the magic number from the header is missing.
    if (messageHeader.magic != DTXMessageHeaderMagic) {
      return InvalidResponsePayload;
    }
    // We should always expect that identifiers are increasing.
    if (messageHeader.conversationIndex == 0 && messageHeader.identifier < request.messageIdentifier) {
      [[FBControlCoreError
        describeFormat:@"Response identifier %d with lower identifier than that requested (%d)", messageHeader.identifier, request.messageIdentifier]
        fail:error];
      return InvalidResponsePayload;
    }
    if (messageHeader.conversationIndex == 1 && messageHeader.identifier != request.messageIdentifier) {
      [[FBControlCoreError
        describeFormat:@"Response identifier %d is not the same as requested identifier (%d)", messageHeader.identifier, request.messageIdentifier]
        fail:error];
      return InvalidResponsePayload;
    }
    // First message in a multi-part fragment has no payload, move onto the next fragment which does.
    if (messageHeader.fragmentCount > 1 && messageHeader.fragmentId == 0) {
      continue;
    }
    // Consume all data from this fragment and accumilate it.
    NSData *fragmentData = [transfer receive:messageHeader.length error:error];
    if (!fragmentData) {
      return InvalidResponsePayload;
    }
    [payloadData appendData:fragmentData];
  }
  return [self consumePayloadData:payloadData messageHeader:messageHeader error:error];
}

+ (ResponsePayload)consumePayloadData:(NSData *)payloadData messageHeader:(DTXMessageHeader)messageHeader error:(NSError **)error
{
  // There is a single payload header at the start of the payload, even if it is a multi-part message.
  DTXMessagePayloadHeader payloadHeader;
  payloadData = [self advanceData:payloadData buffer:&payloadHeader length:sizeof(payloadHeader)];
  uint8 compression = (payloadHeader.flags & 0xFF000) >> 12;
  if (compression != 0) {
    return InvalidResponsePayload;
  }

  // First comes the auxillary data.
  size_t auxillaryDataLength = payloadHeader.auxiliaryLength;
  NSData *auxillaryData = nil;
  if (auxillaryDataLength) {
    payloadData = [self advanceData:payloadData dataOut:&auxillaryData length:auxillaryDataLength];
  }

  // Then comes the return value
  size_t returnValueDataLength = payloadHeader.totalLength - payloadHeader.auxiliaryLength;
  NSData *returnValueData = nil;
  if (returnValueDataLength) {
    payloadData = [self advanceData:payloadData dataOut:&returnValueData length:returnValueDataLength];
  }

  // Then parse the payload items.
  return [self parseReturnValueData:returnValueData auxillaryData:auxillaryData messageHeader:messageHeader error:error];
}

+ (ResponsePayload)parseReturnValueData:(NSData *)returnValueData auxillaryData:(NSData *)auxillaryData messageHeader:(DTXMessageHeader)messageHeader error:(NSError **)error
{
  // Auxillary data comes first. This is typically only used in the handshake
  id auxillaryValues = nil;
  if (auxillaryData && auxillaryData.length > 0) {
    auxillaryValues = [self objectArgumentsFromAuxillaryData:auxillaryData error:error];
    if (!auxillaryValues) {
      return InvalidResponsePayload;
    }
  }

  // Then the return value of the RPC call. For some calls this will be the selector name.
  id returnValue = nil;
  if (returnValueData && returnValueData.length > 0) {
    returnValue = [NSKeyedUnarchiver unarchivedObjectOfClasses:self.supportedReturnSerializerValues fromData:returnValueData error:error];
    if (!returnValue) {
      return InvalidResponsePayload;
    }
    if ([returnValue isKindOfClass:NSError.class]) {
      if (error) {
        *error = returnValue;
      }
      return InvalidResponsePayload;
    }
  }

  return (ResponsePayload) {
    .success = YES,
    .messageIdentifier = messageHeader.identifier,
    .channelCode = messageHeader.channelCode,
    .returnValue = returnValue,
    .auxillaryValues = auxillaryValues,
  };
}

#pragma mark Private Instance Methods

- (ResponsePayload)onChannelIdentifier:(NSString *)channelIdentifier performSelector:(NSString *)selector argumentsData:(nullable NSArray<NSData *> *)argumentsData error:(NSError **)error
{
  NSNumber *channelCode = [self makeChannelWithIdentifier:channelIdentifier error:error];
  if (!channelCode) {
    return InvalidResponsePayload;
  }
  return [self onChannelCode:channelCode.unsignedIntValue performSelector:selector argumentsData:argumentsData error:error];
}

- (ResponsePayload)onChannelCode:(uint32)channelCode performSelector:(NSString *)selector argumentsData:(nullable NSArray<NSData *> *)argumentsData error:(NSError **)error
{
  RequestPayload request = {
    .selector = selector,
    .argumentsData = argumentsData,
    .messageIdentifier = [self nextMessageIdentifier],
    .channelCode = channelCode,
    .expectsReply = YES,
  };
  return [self requestSendAndReceive:request error:error];
}

- (NSNumber *)makeChannelWithIdentifier:(NSString *)identifier error:(NSError **)error
{
  if (self.channels[identifier] == nil) {
    return [[FBControlCoreError
      describeFormat:@"Could not make a channel %@ as it is not one of %@", identifier, self.channels.allKeys]
      fail:error];
  }
  int32_t channelIdentifier = [self nextChannelIdentifier];
  RequestPayload request = {
    .selector = @"_requestChannelWithCode:identifier:",
    .argumentsData = @[
      [FBInstrumentsClient argumentDataForInt32:channelIdentifier],
      [FBInstrumentsClient argumentDataForArgument:identifier],
    ],
    .messageIdentifier = [self nextMessageIdentifier],
    .channelCode = 0,
    .expectsReply = YES,
  };
  ResponsePayload response = [self requestSendAndReceive:request error:error];
  if (response.success == NO) {
    return nil;
  }
  return @(channelIdentifier);
}

- (ResponsePayload)requestSendAndReceive:(RequestPayload)request error:(NSError **)error
{
  ResponsePayload response = [FBInstrumentsClient onConnection:self.connection requestSendAndReceive:request error:error];
  if (response.success == NO) {
    return InvalidResponsePayload;
  }
  self.lastMessageIdentifier = response.messageIdentifier;
  return response;
}

- (uint32)nextMessageIdentifier
{
  uint32 identifier = self.lastMessageIdentifier + 1;
  self.lastMessageIdentifier = identifier;
  return identifier;
}

- (int32_t)nextChannelIdentifier
{
  int32_t identifier = self.lastChannelIdentifier + 1;
  self.lastChannelIdentifier = identifier;
  return identifier;
}

@end
