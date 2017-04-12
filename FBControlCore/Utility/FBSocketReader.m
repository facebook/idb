/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSocketReader.h"

#import <sys/socket.h>
#import <netinet/in.h>
#import <CoreFoundation/CoreFoundation.h>
#import <FBControlCore/FBControlCore.h>

#import "FBControlCoreError.h"

@interface FBSocketReader_Connection : NSObject <FBFileConsumer>

@property (nonatomic, strong, readonly) FBFileReader *reader;
@property (nonatomic, strong, readonly) FBFileWriter *writer;
@property (nonatomic, strong, readonly) id<FBSocketConsumer> consumer;
@property (nonatomic, strong, readonly) dispatch_queue_t completionQueue;
@property (nonatomic, strong, readonly) void (^completionHandler)(void);

@end

@implementation FBSocketReader_Connection

- (instancetype)initWithConsumer:(id<FBSocketConsumer>)consumer fileHandle:(NSFileHandle *)fileHandle completionQueue:(dispatch_queue_t)completionQueue completionHandler:(void(^)(void))completionHandler
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumer = consumer;
  _writer = [FBFileWriter writerWithFileHandle:fileHandle blocking:NO];
  _reader = [FBFileReader readerWithFileHandle:fileHandle consumer:self];
  _completionQueue = completionQueue;
  _completionHandler = completionHandler;

  return self;
}

- (BOOL)startConsumingWithError:(NSError **)error
{
  if (![self.reader startReadingWithError:error]) {
    _completionHandler = nil;
    _completionQueue = nil;
    return NO;
  }
  return YES;
}

#pragma mark FBFileConsumer Implementation

- (void)consumeData:(NSData *)data
{
  [self.consumer consumeData:data writeBack:self.writer];
}

- (void)consumeEndOfFile
{
  [self.writer consumeEndOfFile];
  dispatch_async(self.completionQueue, self.completionHandler);
  _completionHandler = nil;
  _completionQueue = nil;
}

@end

@interface FBSocketReader ()

@property (nonatomic, assign, readonly) in_port_t port;
@property (nonatomic, strong, readonly) id<FBSocketReaderDelegate> delegate;
@property (nonatomic, strong, readonly) dispatch_queue_t acceptQueue;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSNumber *, FBSocketReader_Connection *> *connections;

@property (nonatomic, strong, readwrite) dispatch_source_t acceptSource;

@end

@implementation FBSocketReader

+ (instancetype)socketReaderOnPort:(in_port_t)port delegate:(id<FBSocketReaderDelegate>)delegate
{
  return [[self alloc] initWithPort:port delegate:delegate];
}

- (instancetype)initWithPort:(in_port_t)port delegate:(id<FBSocketReaderDelegate>)delegate
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _port = port;
  _delegate = delegate;
  _acceptQueue = dispatch_queue_create("com.facebook.fbsimulatorcontrol.socket.accept", DISPATCH_QUEUE_SERIAL);
  _connections = [NSMutableDictionary dictionary];

  return self;
}

- (BOOL)startListeningWithError:(NSError **)error
{
  if (self.acceptSource) {
    return [[FBControlCoreError
      describe:@"Cannot start listening, socket is already listening"]
      failBool:error];
  }
  return [self createSocketWithPort:self.port error:error];
}

- (BOOL)stopListeningWithError:(NSError **)error
{
  if (!self.acceptSource) {
    return [[FBControlCoreError
      describe:@"Cannot stop listening, there is no active socket"]
      failBool:error];
  }
  dispatch_source_cancel(self.acceptSource);
  self.acceptSource = nil;
  return YES;
}

- (BOOL)createSocketWithPort:(in_port_t)port error:(NSError **)error
{
  // Get the Socket, set some options
  int socketHandle = socket(PF_INET6, SOCK_STREAM, IPPROTO_TCP);
  if (socket <= 0) {
    return [[FBControlCoreError
      describeFormat:@"Failed to create a socket with errno %d", errno]
      failBool:error];
  }
  int flagTrue = 1;
  setsockopt(socketHandle, SOL_SOCKET, SO_REUSEADDR, &flagTrue, sizeof(flagTrue));

  // Bind the Socket.
  struct sockaddr_in6 sockaddr6;
  memset(&sockaddr6, 0, sizeof(sockaddr6));
  sockaddr6.sin6_len = sizeof(sockaddr6);
  sockaddr6.sin6_family = AF_INET6;
  sockaddr6.sin6_port = htons(self.port);
  sockaddr6.sin6_addr = in6addr_any;
  int result = bind(socketHandle, (struct sockaddr *)&sockaddr6, sizeof(sockaddr6));
  if (result != 0) {
    return [[FBControlCoreError
      describeFormat:@"Failed to bind the socket with errno %d", errno]
      failBool:error];
  }

  // Start Listening
  result = listen(socketHandle, 10);
  if (result != 0) {
    return [[FBControlCoreError
      describeFormat:@"Failed to listen on the socket with errno %d", errno]
      failBool:error];
  }

  // Prepare the Accept Source
  dispatch_queue_t acceptQueue = self.acceptQueue;
  self.acceptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t) socketHandle, 0, acceptQueue);
  __weak typeof(self) weakSelf = self;

  // Dispatch read events from the accept source.
  dispatch_source_set_event_handler(self.acceptSource, ^{
    [weakSelf accept:socketHandle error:nil];
  });
  // Start reading socket.
  dispatch_resume(self.acceptSource);
  return YES;
}

- (BOOL)accept:(int)socketHandle error:(NSError **)error
{
  // Accept the Connnection.
  struct sockaddr_in6 address;
  socklen_t addressLength = sizeof(address);
  int acceptHandle = accept(socketHandle, (struct sockaddr *) &address, &addressLength);
  if (!acceptHandle) {
    return [[FBControlCoreError
      describeFormat:@"accept() failed with error %d", errno]
      failBool:error];
  }

  // Create the Consumer.
  id<FBSocketConsumer> consumer = [self.delegate consumerWithClientAddress:address.sin6_addr];
  NSFileHandle *fileHandle = [[NSFileHandle alloc] initWithFileDescriptor:acceptHandle closeOnDealloc:YES];
  __weak typeof(self) weakSelf = self;

  // Create the Connection
  FBSocketReader_Connection *connection = [[FBSocketReader_Connection alloc] initWithConsumer:consumer fileHandle:fileHandle completionQueue:self.acceptQueue completionHandler:^{
    [weakSelf.connections removeObjectForKey:@(acceptHandle)];
  }];
  // Bail early if the connection could not be consumed
  if (![connection startConsumingWithError:error]) {
    return NO;
  }
  // Retain the connection, it will be releaed in the completion.
  self.connections[@(acceptHandle)] = connection;
  return YES;
}

@end
