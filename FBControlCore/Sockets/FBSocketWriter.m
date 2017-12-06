/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSocketWriter.h"

#import "FBSocketReader.h"
#import "FBFileReader.h"
#import "FBFileWriter.h"
#import "FBControlCoreError.h"

@interface FBSocketWriter_Connection : NSObject <FBFileConsumer>

@property (nonatomic, strong, readonly) id<FBSocketConsumer> consumer;

@property (nonatomic, strong, nullable, readonly) NSFileHandle *fileHandle;
@property (nonatomic, strong, nullable, readonly) FBFileReader *reader;
@property (nonatomic, strong, nullable, readonly) FBFileWriter *writer;

@end

@implementation FBSocketWriter_Connection

- (instancetype)initWithConsumer:(id<FBSocketConsumer>)consumer fileHandle:(NSFileHandle *)fileHandle
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumer = consumer;
  _fileHandle = fileHandle;

  return self;
}

#pragma mark Lifecycle

- (FBFuture<NSNull *> *)startWriting
{
  NSError *error = nil;
  _writer = [FBFileWriter asyncWriterWithFileHandle:self.fileHandle error:&error];
  if (!_writer) {
    [self tearDown];
    return [FBFuture futureWithError:error];
  }
  _reader = [FBFileReader readerWithFileHandle:self.fileHandle consumer:self];
  return [[_reader
    startReading]
    onQueue:dispatch_get_main_queue() chain:^(FBFuture<NSNull *> *future) {
      if (future.result) {
        [self.consumer writeBackAvailable:self];
      } else {
        [self tearDown];
      }
      return future;
    }];
}

#pragma mark FBFileConsuemr

- (void)consumeData:(NSData *)data
{
  [self.writer consumeData:data];
}

- (void)consumeEndOfFile
{
  [self.writer consumeEndOfFile];
  [self tearDown];
}

#pragma mark Teardown

- (void)tearDown
{
  _reader = nil;
  _writer = nil;
}

@end

@interface FBSocketWriter ()

@property (nonatomic, strong, readonly) id<FBSocketConsumer> consumer;
@property (nonatomic, copy, readonly) NSString *host;
@property (nonatomic, assign, readonly) in_port_t port;

@property (nonatomic, strong, readwrite) FBSocketWriter_Connection *connection;

@end

@implementation FBSocketWriter

#pragma mark Initializers

+ (instancetype)writerForHost:(NSString *)host port:(in_port_t)port consumer:(id<FBSocketConsumer>)consumer
{
  return [[self alloc] initWithHost:host port:port consumer:consumer];
}

- (instancetype)initWithHost:(NSString *)host port:(in_port_t)port consumer:(id<FBSocketConsumer>)consumer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumer = consumer;
  _host = host;
  _port = port;

  return self;
}

#pragma mark Public Methods

- (FBFuture<NSNull *> *)startWriting
{
  if (self.connection) {
    return [[FBControlCoreError
      describeFormat:@"There is an existing connection for %@ %d", self.host, self.port]
      failFuture];
  }

  // Resolve the address
  NSError *error = nil;
  struct sockaddr_in6 address = [FBSocketWriter addressForHostname:self.host port:self.port error:&error];
  if (address.sin6_port == 0) {
    return [FBFuture futureWithError:error];
  }

  // Create a socket
  int socketHandle = socket(AF_INET6, SOCK_STREAM, 0);
  if (socketHandle < 0) {
    return [[FBControlCoreError
      describeFormat:@"Failed to create a socket for %@:%d", self.host, self.port]
      failFuture];
  }

  // Listen to the socket
  int code = connect(socketHandle, (const struct sockaddr *) &address, sizeof(struct sockaddr_in6));
  if (code < 0) {
    return [[FBControlCoreError
      describeFormat:@"Failed to listen to  socket for %@:%d error %d", self.host, self.port, errno]
      failFuture];
  }
  return [[self
    createConnectionForSocket:socketHandle]
    onQueue:dispatch_get_main_queue() map:^(FBSocketWriter_Connection *connection) {
      self.connection = connection;
      return NSNull.null;
    }];
}

- (FBFuture<NSNull *> *)stopWriting
{
  return [FBFuture futureWithResult:NSNull.null];
}

#pragma mark Private Methods

- (FBFuture<FBSocketWriter_Connection *> *)createConnectionForSocket:(int)socket
{
  NSFileHandle *handle = [[NSFileHandle alloc] initWithFileDescriptor:socket closeOnDealloc:YES];
  FBSocketWriter_Connection *connection = [[FBSocketWriter_Connection alloc] initWithConsumer:self.consumer fileHandle:handle];
  return [[connection startWriting] mapReplace:connection];
}

+ (struct sockaddr_in6)addressForHostname:(NSString *)hostName port:(in_port_t)port error:(NSError **)error
{
  struct sockaddr_in6 address;
  address.sin6_port = 0;

  CFHostRef host = CFHostCreateWithName(NULL, (__bridge CFStringRef _Nonnull)(hostName));
  CFStreamError streamError;
  Boolean success = CFHostStartInfoResolution(host, kCFHostAddresses, &streamError);
  if (!success) {
    CFRelease(host);
    [[FBControlCoreError
      describeFormat:@"Failed to start addressing for %@", hostName]
      fail:error];
    return address;
  }

  success = false;
  NSArray<NSData *> *addresses = (__bridge NSArray<NSData *> *)(CFHostGetAddressing(host, &success));
  CFRelease(host);
  if (!success) {
    [[FBControlCoreError
      describeFormat:@"Could not get address for %@", hostName]
      fail:error];
    return address;
  }

  NSData *addressData = addresses.firstObject;
  memcpy(&address, addressData.bytes, addressData.length);
  address.sin6_port = htons(port);
  return address;
}

@end
