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

#import "FBSocketServer.h"
#import "FBControlCoreError.h"

@interface FBSocketReader_Connection : NSObject <FBFileConsumer>

@property (nonatomic, strong, readonly) id<FBSocketConsumer> consumer;

@property (nonatomic, strong, nullable, readonly) NSFileHandle *fileHandle;
@property (nonatomic, strong, nullable, readonly) FBFileReader *reader;
@property (nonatomic, strong, nullable, readonly) FBFileWriter *writer;

@property (nonatomic, strong, nullable, readonly) dispatch_queue_t completionQueue;
@property (nonatomic, strong, nullable, readonly) void (^completionHandler)(void);

@end

@implementation FBSocketReader_Connection

- (instancetype)initWithConsumer:(id<FBSocketConsumer>)consumer fileHandle:(NSFileHandle *)fileHandle completionQueue:(dispatch_queue_t)completionQueue completionHandler:(void(^)(void))completionHandler
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _fileHandle = fileHandle;
  _consumer = consumer;
  _completionQueue = completionQueue;
  _completionHandler = completionHandler;

  return self;
}

- (BOOL)startConsumingWithError:(NSError **)error
{
  _writer = [FBFileWriter asyncWriterWithFileHandle:self.fileHandle error:error];
  if (!_writer) {
    [self teardown];
    return NO;
  }
  _reader = [FBFileReader readerWithFileHandle:self.fileHandle consumer:self];

  if (![self.reader startReadingWithError:error]) {
    [self teardown];
    return NO;
  }
  [self.consumer writeBackAvailable:self.writer];
  return YES;
}

- (void)teardown
{
  _completionHandler = nil;
  _completionQueue = nil;
}

#pragma mark FBFileConsumer Implementation

- (void)consumeData:(NSData *)data
{
  [self.consumer consumeData:data];
}

- (void)consumeEndOfFile
{
  [self.consumer consumeEndOfFile];
  [self.writer consumeEndOfFile];
  dispatch_async(self.completionQueue, self.completionHandler);
  [self teardown];
}


@end

@interface FBSocketReader () <FBSocketServerDelegate>

@property (nonatomic, strong, readonly) FBSocketServer *server;
@property (nonatomic, strong, readonly) id<FBSocketReaderDelegate> delegate;
@property (nonatomic, strong, readonly) NSMutableDictionary<NSNumber *, FBSocketReader_Connection *> *connections;

@end

@implementation FBSocketReader

@synthesize queue = _queue;

#pragma mark Initializers

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

  _delegate = delegate;
  _server = [FBSocketServer socketServerOnPort:port delegate:self];
  _connections = [NSMutableDictionary dictionary];
  _queue = dispatch_queue_create("com.facebook.fbsimulatorcontrol.socket.accept", DISPATCH_QUEUE_SERIAL);

  return self;
}

#pragma mark Public

- (FBFuture<NSNull *> *)startListening
{
  return [self.server startListening];
}

- (FBFuture<NSNull *> *)stopListening
{
  return [self.server stopListening];
}

#pragma mark FBSocketServerDelegate

- (void)socketServer:(FBSocketServer *)server clientConnected:(struct in6_addr)address handle:(NSFileHandle *)fileHandle
{
  // Create the Consumer.
  id<FBSocketConsumer> consumer = [self.delegate consumerWithClientAddress:address];
  __weak typeof(self) weakSelf = self;

  // Create the Connection
  FBSocketReader_Connection *connection = [[FBSocketReader_Connection alloc] initWithConsumer:consumer fileHandle:fileHandle completionQueue:self.queue completionHandler:^{
    [weakSelf.connections removeObjectForKey:@(fileHandle.fileDescriptor)];
  }];
  // Bail early if the connection could not be consumed
  NSError *error = nil;
  if (![connection startConsumingWithError:&error]) {
    return;
  }
  // Retain the connection, it will be released in the completion.
  self.connections[@(fileHandle.fileDescriptor)] = connection;
}

@end
