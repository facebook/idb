/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAMDServiceConnection.h"

#import "FBAFCConnection.h"
#import "FBDeviceControlError.h"

typedef uint32_t HeaderIntType;
static const NSUInteger HeaderLength = sizeof(HeaderIntType);

// There's an upper limit on the number of bytes we can read at once
static size_t ReadBufferSize = 1024 * 4;

@interface FBAMDServiceConnection ()

- (ssize_t)send:(const void *)buffer size:(size_t)size;
- (ssize_t)receive:(void *)buffer size:(size_t)size;

@end

@interface FBAMDServiceConnection_FileReader : NSObject <FBFileReader>

@property (nonatomic, strong, readonly) id<FBDataConsumer> consumer;
@property (nonatomic, strong, readonly) FBAMDServiceConnection *connection;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNumber *> *finishedReadingMutable;

@end

@implementation FBAMDServiceConnection_FileReader

@synthesize state = _state;

- (instancetype)initWithServiceConnection:(FBAMDServiceConnection *)connection consumer:(id<FBDataConsumer>)consumer queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _connection = connection;
  _consumer = consumer;
  _queue = queue;
  _state = FBFileReaderStateNotStarted;
  _finishedReadingMutable = FBMutableFuture.future;

  return self;
}

- (FBFuture<NSNull *> *)startReading
{
  if (self.state != FBFileReaderStateNotStarted) {
    return [[FBDeviceControlError
      describeFormat:@"Cannot start reading in state %lu", (unsigned long)self.state]
      failFuture];
  }

  FBAMDServiceConnection *connection = self.connection;
  id<FBDataConsumer> consumer = self.consumer;
  dispatch_async(self.queue, ^{
    void *buffer = alloca(ReadBufferSize);
    while (self.state == FBFileReaderStateReading && self.finishedReadingMutable.state == FBFutureStateRunning) {
      ssize_t readBytes = [connection receive:buffer size:ReadBufferSize];
      if (readBytes < 1) {
        break;
      }
      NSData *data = [[NSData alloc] initWithBytes:buffer length:(size_t) readBytes];
      [consumer consumeData:data];
    }
    [consumer consumeEndOfFile];
    self->_state = FBFileReaderStateFinishedReadingNormally;
  });
  _state = FBFileReaderStateReading;

  return FBFuture.empty;
}

- (FBFuture<NSNumber *> *)stopReading
{
  if (self.state == FBFileReaderStateNotStarted) {
    return [[FBDeviceControlError
      describe:@"Cannot stop reading when reading has not started"]
      failFuture];
  }
  if (self.state != FBFileReaderStateReading) {
    return self.finishedReadingMutable;
  }
  _state = FBFileReaderStateFinishedReadingByCancellation;
  [self.finishedReadingMutable resolveWithResult:@(FBFileReaderStateFinishedReadingByCancellation)];
  return self.finishedReadingMutable;
}

- (FBFuture<NSNumber *> *)finishedReadingWithTimeout:(NSTimeInterval)timeout
{
  return [[[self
    finishedReading]
    timeout:timeout waitingFor:@"Process Reading to Finish"]
    onQueue:self.queue handleError:^(NSError *_) {
      return [self stopReading];
    }];
}

- (FBFuture<NSNumber *> *)finishedReading
{
  return self.finishedReadingMutable;
}

@end

@implementation FBAMDServiceConnection

#pragma mark Initializers

+ (instancetype)connectionWithName:(NSString *)name connection:(AMDServiceConnectionRef)connection device:(AMDeviceRef)device calls:(AMDCalls)calls logger:(id<FBControlCoreLogger>)logger
{
  // Use Raw transfer when there's no Secure Context, otherwise we must use the service connection wrapping.
  AMSecureIOContext secureIOContext = calls.ServiceConnectionGetSecureIOContext(connection);
  [logger logFormat:@"Constructing service connection for %@ %@ Secure", name, secureIOContext ? @"is" : @"is not"];
  return [[FBAMDServiceConnection alloc] initWithName:name connection:connection device:device calls:calls logger:logger];
}

- (instancetype)initWithName:(NSString *)name connection:(AMDServiceConnectionRef)connection device:(AMDeviceRef)device calls:(AMDCalls)calls logger:(id<FBControlCoreLogger>)logger;
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _name = name;
  _connection = connection;
  _device = device;
  _calls = calls;
  _logger = logger;
  // There's an upper limit on the number of bytes we can read at once
  _readBufferSize = 1024 * 4;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"%@ %@", self.name, self.connection];
}

#pragma mark plist Messaging

- (BOOL)sendMessage:(id)message error:(NSError **)error
{
  int result = self.calls.ServiceConnectionSendMessage(self.connection, (__bridge CFPropertyListRef)(message), kCFPropertyListBinaryFormat_v1_0, NULL, NULL, NULL);
  if (result != 0) {
    NSString *errorDescription = CFBridgingRelease(self.calls.CopyErrorText(result));
    return [[FBDeviceControlError
      describeFormat:@"Failed to send message %@ (%@ code %d)", errorDescription, message, result]
      failBool:error];
  }
  return YES;
}

- (id)receiveMessageWithError:(NSError **)error
{
  CFTypeRef message = NULL;
  int result = self.calls.ServiceConnectionReceiveMessage(self.connection, &message, NULL, NULL, NULL, NULL);
  if (result != 0) {
    NSString *errorDescription = CFBridgingRelease(self.calls.CopyErrorText(result));
    return [[FBDeviceControlError
      describeFormat:@"Failed to receive message (%@): code %d", errorDescription, result]
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

#pragma mark AFC

- (FBAFCConnection *)asAFCConnectionWithCalls:(AFCCalls)calls callback:(AFCNotificationCallback)callback logger:(id<FBControlCoreLogger>)logger
{
  AFCConnectionRef afcConnection = calls.Create(
    0x0,
    self.calls.ServiceConnectionGetSocket(self.connection),
    0x0,
    callback,
    0x0
  );
  // We need to apply the Secure Context if it's present on the service connection.
  AMSecureIOContext secureIOContext = self.calls.ServiceConnectionGetSecureIOContext(self.connection);;
  if (secureIOContext != NULL) {
    calls.SetSecureContext(afcConnection, secureIOContext);
  }
  return [[FBAFCConnection alloc] initWithConnection:afcConnection calls:calls logger:self.logger];
}

#pragma mark FBAMDServiceConnectionTransfer Implementation

// There's an upper limit on the number of bytes we can receive at once
static size_t SendBufferSize = 1024 * 4;

- (BOOL)send:(NSData *)data error:(NSError **)error
{
  // Keep track of the number of bytes we can send.
  size_t bytesRemaining = data.length;

  // Start a loop that ends when there's no more bytes to send
  while (bytesRemaining > 0) {
    // Send the bytes now
    NSRange sendRange = NSMakeRange(data.length - data.length, MIN(SendBufferSize, bytesRemaining));
    NSData *chunkData = [data subdataWithRange:sendRange];
    ssize_t result = [self send:chunkData.bytes size:chunkData.length];
    // A negative return indicates error.
    if (result == -1) {
      return [[FBDeviceControlError
        describeFormat:@"Failure in send of %zu bytes: %s", chunkData.length, strerror(errno)]
        failBool:error];
    }
    // End of file.
    if (result == 0) {
      break;
    }
    // Check an over-write to prevent unsigned integer overflow.
    size_t sentBytes = (size_t) result;
    if (sentBytes > bytesRemaining) {
      return [[FBDeviceControlError
        describeFormat:@"Failure in send: Sent %zu bytes but only %zu bytes remaining", sentBytes, bytesRemaining]
        failBool:error];
    }
    // Otherwise keep going and decrement the number of remaining bytes to send.
    bytesRemaining -= sentBytes;
  }

  // Check that we've sent the right number of bytes.
  if (bytesRemaining != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to send %zu bytes, %zu remaining", data.length, bytesRemaining]
      failBool:error];
  }
  return YES;
}

- (BOOL)sendWithLengthHeader:(NSData *)data error:(NSError **)error
{
  HeaderIntType length = (HeaderIntType) data.length;
  HeaderIntType lengthWire = OSSwapHostToBigInt32(length); // The host (native) length should be converted endianness of remote (ARM/Apple Silicon).
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

- (BOOL)sendUnsignedInt32:(uint32_t)value error:(NSError **)error
{
  NSData *data = [[NSData alloc] initWithBytes:&value length:sizeof(uint32_t)];
  return [self send:data error:error];
}

- (NSData *)receive:(size_t)size error:(NSError **)error
{
  // Create a buffer that contains the data to return and how to append it from the enumerator
  NSMutableData *data = NSMutableData.data;
  void(^enumerator)(NSData *) = ^(NSData *chunk){
    [data appendData:[chunk copy]];
  };
  // Start the byte recieve.
  BOOL success = [self enumateReceiveOfLength:size chunkSize:ReadBufferSize enumerator:enumerator error:error];
  if (!success) {
    return nil;
  }
  return data;
}

- (BOOL)receive:(size_t)size toFile:(NSFileHandle *)fileHandle error:(NSError **)error
{
  void(^enumerator)(NSData *) = ^(NSData *chunk){
    [fileHandle writeData:chunk];
  };
  return [self enumateReceiveOfLength:size chunkSize:ReadBufferSize enumerator:enumerator error:error];
}

- (BOOL)receive:(void *)destination ofSize:(size_t)size error:(NSError **)error
{
  NSData *data = [self receive:size error:error];
  if (!data) {
    return NO;
  }
  memcpy(destination, data.bytes, data.length);
  return YES;
}

- (NSData *)receiveUpTo:(size_t)size error:(NSError **)error
{
  // Create a buffer that contains the data
  void *buffer = alloca(size);
  // Read the underlying bytes.
  ssize_t result = [self receive:buffer size:size];
  // End of file.
  if (result == 0) {
    return NSData.data;
  }
  // A negative return indicates an error
  if (result == -1) {
    return [[FBDeviceControlError
      describeFormat:@"Failure in receive of up to %zu bytes: %s", size, strerror(errno)]
      fail:error];
  }
  size_t readBytes = (size_t) result;
  return [[NSData alloc] initWithBytes:buffer length:readBytes];
}

- (BOOL)receiveUnsignedInt32:(uint32_t *)valueOut error:(NSError **)error
{
  return [self receive:valueOut ofSize:sizeof(uint32_t) error:error];
}

- (BOOL)receiveUnsignedInt64:(uint64_t *)valueOut error:(NSError **)error
{
  return [self receive:valueOut ofSize:sizeof(uint64_t) error:error];
}

- (id<FBFileReader>)readFromConnectionWritingToConsumer:(id<FBDataConsumer>)consumer onQueue:(dispatch_queue_t)queue
{
  return [[FBAMDServiceConnection_FileReader alloc] initWithServiceConnection:self consumer:consumer queue:queue];
}

- (id<FBDataConsumer, FBDataConsumerLifecycle>)writeWithConsumerWritingOnQueue:(dispatch_queue_t)queue
{
  return [FBBlockDataConsumer asynchronousDataConsumerOnQueue:queue consumer:^(NSData *data) {
    [self send:data error:nil];
  }];
}

#pragma mark Private

- (ssize_t)send:(const void *)buffer size:(size_t)size
{
  return self.calls.ServiceConnectionSend(self.connection, buffer, size);
}

- (ssize_t)receive:(void *)buffer size:(size_t)size
{
  return self.calls.ServiceConnectionReceive(self.connection, buffer, size);
}

- (BOOL)enumateReceiveOfLength:(size_t)size chunkSize:(size_t)chunkSize enumerator:(void(^)(NSData *))enumerator error:(NSError **)error
{
  // Create a buffer that contains the incremental enumerated data.
  void *buffer = alloca(chunkSize);

  // Start reading in a loop, until there's no more bytes to read.
  size_t bytesRemaining = size;
  while (bytesRemaining > 0) {
    // Don't read more bytes than are remaining.
    size_t maxReadBytes = MIN(chunkSize, bytesRemaining);
    ssize_t result = [self receive:buffer size:maxReadBytes];
    // End of file.
    if (result == 0) {
      break;
    }
    // A negative return indicates an error
    if (result == -1) {
      return [[FBDeviceControlError
        describeFormat:@"Failure in receive of %zu bytes: %s", maxReadBytes, strerror(errno)]
        failBool:error];
    }
    // Check an over-read to prevent unsigned integer overflow.
    size_t readBytes = (size_t) result;
    if (readBytes > bytesRemaining) {
      return [[FBDeviceControlError
        describeFormat:@"Failure in receive: Read %zu bytes but only %zu bytes remaining", readBytes, bytesRemaining]
        failBool:error];
    }
    // Decrement the number of bytes to read and pass it to the callback
    bytesRemaining -= readBytes;
    NSData *readData = [[NSData alloc] initWithBytesNoCopy:buffer length:readBytes freeWhenDone:NO];
    enumerator(readData);
  }

  // Check that we've read the right number of bytes.
  if (bytesRemaining != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to receive %zu bytes, %zu remaining to read and eof reached.", size, bytesRemaining]
      failBool:error];
  }
  return YES;
}

@end
