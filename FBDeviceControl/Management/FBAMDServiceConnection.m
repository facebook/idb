/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAMDServiceConnection.h"

#import "FBDeviceControlError.h"
#import "FBServiceConnectionClient.h"

typedef uint32_t HeaderIntType;
static const NSUInteger HeaderLength = sizeof(HeaderIntType);

@implementation FBAMDServiceConnection

#pragma mark Initializers

- (instancetype)initWithServiceConnection:(AMDServiceConnectionRef)connection device:(AMDeviceRef)device calls:(AMDCalls)calls logger:(id<FBControlCoreLogger>)logger;
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _connection = connection;
  _device = device;
  _calls = calls;
  _logger = logger;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"%@", self.connection];
}

#pragma mark Raw Data

// There's an upper limit on the number of bytes we can receive at once
static size_t SendBufferSize = 1024 * 4;

- (BOOL)send:(NSData *)data error:(NSError **)error
{
  // Keep track of the number of bytes we can send.
  size_t bytesRemaning = data.length;

  // Start a loop that ends when there's no more bytes to send
  while (bytesRemaning > 0) {
    // Send the bytes now
    NSRange sendRange = NSMakeRange(data.length - data.length, MIN(SendBufferSize, bytesRemaning));
    NSData *chunkData = [data subdataWithRange:sendRange];
    size_t sentBytes = self.calls.ServiceConnectionSend(self.connection, chunkData.bytes, chunkData.length);
    // If there's no data sent then break out now.
    if (sentBytes < 1) {
      break;
    }
    // Otherwise keep going and decrement the number of remaining bytes to send.
    bytesRemaning -= sentBytes;
  }

  // Check that we've sent the right number of bytes.
  if (bytesRemaning != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to send %zu bytes from AMDServiceConnectionReceive, %zu remaining", data.length, bytesRemaning]
      failBool:error];
  }
  return YES;
}

- (BOOL)sendWithLengthHeader:(NSData *)data error:(NSError **)error
{
  HeaderIntType length = (HeaderIntType) data.length;
  HeaderIntType lengthWire = EndianU32_NtoB(length); // The native length should be converted to big-endian (ARM).
  NSData *lengthData = [[NSData alloc] initWithBytes:&lengthWire length:HeaderLength];
  // Write the length data.
  if (![self send:lengthData error:error]) {
    return NO;
  }
  // Then send the actual payload.
  if (![self send:data error:error]) {
   return NO;
  }
  return YES;
}

// There's an upper limit on the number of bytes we can read at once
static size_t ReadBufferSize = 1024 * 4;

- (NSData *)receive:(size_t)size error:(NSError **)error
{
  // Create a buffer that contains the data to return and a temp buffer for reading into.
  NSMutableData *data = NSMutableData.data;
  void *buffer = alloca(ReadBufferSize);

  // Start reading in a loop, until there's no more bytes to read.
  size_t bytesRemaining = size;
  while (bytesRemaining > 0) {
    // Don't read more bytes than are remaining.
    size_t maxReadBytes = MIN(ReadBufferSize, bytesRemaining);
    size_t readBytes = self.calls.ServiceConnectionReceive(self.connection, buffer, maxReadBytes);
    // If there's no more bytes to read then break out now
    if (readBytes < 1) {
      break;
    }
    // Otherwise decrement the number of bytes to read and add it to the return buffer.
    bytesRemaining -= readBytes;
    [data appendBytes:buffer length:readBytes];
  }

  // Check that we've read the right number of bytes.
  if (bytesRemaining != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to receive %zu bytes from AMDServiceConnectionReceive, %zu remaining to read", size, bytesRemaining]
      fail:error];
  }
  return data;
}

#pragma mark plist Messaging

- (BOOL)sendMessage:(id)message error:(NSError **)error
{
  int result = self.calls.ServiceConnectionSendMessage(self.connection, (__bridge CFPropertyListRef)(message), kCFPropertyListBinaryFormat_v1_0, NULL, NULL, NULL);
  if (result != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to send message %@, code %d", message, result]
      failBool:error];
  }
  return YES;
}

- (id)receiveMessageWithError:(NSError **)error
{
  CFTypeRef message = NULL;
  int result = self.calls.ServiceConnectionReceiveMessage(self.connection, &message, NULL, NULL, NULL, NULL);
  if (result != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to recieve message with code %d", result]
      fail:error];
  }
  return CFBridgingRelease(message);
}

- (id)sendAndReceiveMessage:(id)message error:(NSError **)error
{
  if (![self sendMessage:message error:error]) {
    return nil;
  }
  return [self receiveMessageWithError:error];
}

#pragma mark Streams

- (FBFuture<NSNull *> *)consume:(id<FBDataConsumer>)consumer onQueue:(dispatch_queue_t)queue
{
  return [FBFuture
    onQueue:queue resolve:^{
      void *buffer = alloca(ReadBufferSize);
      while (true) {
        size_t readBytes = self.calls.ServiceConnectionReceive(self.connection, buffer, ReadBufferSize);
        if (readBytes < 1) {
          [consumer consumeEndOfFile];
          return FBFuture.empty;
        }
        NSData *data = [[NSData alloc] initWithBytes:buffer length:readBytes];
        [consumer consumeData:data];
      }
    }];
}

#pragma mark Lifecycle

- (BOOL)invalidateWithError:(NSError **)error
{
  if (!_connection) {
    return [[FBDeviceControlError
      describe:@"No connection to invalidate"]
      failBool:error];
  }
  NSString *connectionDescription = CFBridgingRelease(CFCopyDescription(self.connection));
  [self.logger logFormat:@"Invalidating Connection %@", connectionDescription];
  int status = self.calls.ServiceConnectionInvalidate(self.connection);
  if (status != 0) {
    NSString *errorDescription = CFBridgingRelease(self.calls.CopyErrorText(status));
    return [[FBDeviceControlError
      describeFormat:@"Failed to invalidate connection %@ with error %@", connectionDescription, errorDescription]
      failBool:error];
  }
  [self.logger logFormat:@"Invalidated connection %@", connectionDescription];
  // AMDServiceConnectionInvalidate does not release the connection.
  CFRelease(_connection);
  _connection = NULL;
  return YES;
}

- (FBFutureContext<FBServiceConnectionClient *> *)makeClientWithLogger:(id<FBControlCoreLogger>)logger queue:(dispatch_queue_t)queue
{
  return [FBServiceConnectionClient clientForServiceConnection:self queue:queue logger:logger];
}

#pragma mark Properties

- (int)socket
{
  return self.calls.ServiceConnectionGetSocket(self.connection);
}

- (BOOL)secureIOContext
{
  return (BOOL) self.calls.ServiceConnectionGetSecureIOContext(self.connection);
}

@end
