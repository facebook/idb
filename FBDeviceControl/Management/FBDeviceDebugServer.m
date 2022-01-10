/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceDebugServer.h"

#import <FBControlCore/FBControlCore.h>

#import "FBAMDServiceConnection.h"

@interface FBDeviceDebugServer_TwistedPairFiles : NSObject

@property (nonatomic, assign, readonly) int socket;
@property (nonatomic, strong, readonly) FBAMDServiceConnection *connection;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) dispatch_queue_t socketToConnectionQueue;
@property (nonatomic, strong, readonly) dispatch_queue_t connectionToSocketQueue;

@end

@implementation FBDeviceDebugServer_TwistedPairFiles

- (instancetype)initWithSocket:(int)socket connection:(FBAMDServiceConnection *)connection logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _socket = socket;
  _connection = connection;
  _logger = logger;
  _socketToConnectionQueue = dispatch_queue_create("com.facebook.fbdevicecontrol.debugserver.socket_to_connection", DISPATCH_QUEUE_SERIAL);
  _connectionToSocketQueue = dispatch_queue_create("com.facebook.fbdevicecontrol.debugserver.connection_to_socket", DISPATCH_QUEUE_SERIAL);

  return self;
}

static size_t const ConnectionReadSizeLimit = 1024;

- (FBFuture<NSNull *> *)startWithError:(NSError **)error
{
  if (@available(macOS 10.15, *)) {
    id<FBControlCoreLogger> logger = self.logger;
    int socket = self.socket;
    NSFileHandle *socketReadHandle = [[NSFileHandle alloc] initWithFileDescriptor:socket closeOnDealloc:NO];
    NSFileHandle *socketWriteHandle = [[NSFileHandle alloc] initWithFileDescriptor:socket closeOnDealloc:NO];
    FBAMDServiceConnection *connection = self.connection;
    FBMutableFuture<NSNull *> *socketReadCompleted = FBMutableFuture.future;
    FBMutableFuture<NSNull *> *connectionReadCompleted = FBMutableFuture.future;
    dispatch_async(self.socketToConnectionQueue, ^{
      while (socketReadCompleted.state == FBFutureStateRunning && connectionReadCompleted.state == FBFutureStateRunning) {
        NSError *innerError = nil;
        NSData *data = [socketReadHandle availableData];
        if (data.length == 0) {
          [logger log:@"Socket read reached end of file"];
          break;
        }
        if (![connection send:data error:&innerError]) {
          [logger logFormat:@"Sending data to remote debugserver failed: %@", innerError];
          break;
        }
      }
      [logger logFormat:@"Exiting socket %d read loop", socket];
      [socketReadCompleted resolveWithResult:NSNull.null];
    });
    dispatch_async(self.connectionToSocketQueue, ^{
      while (socketReadCompleted.state == FBFutureStateRunning && connectionReadCompleted.state == FBFutureStateRunning) {
        NSError *innerError = nil;
        NSData *data = [connection receiveUpTo:ConnectionReadSizeLimit error:&innerError];
        if (data.length == 0) {
          [logger logFormat:@"debugserver read ended: %@", innerError];
          break;
        }
        if (![socketWriteHandle writeData:data error:&innerError]) {
          [logger logFormat:@"Socket write failed: %@", innerError];
          break;
        }
      }
      [logger logFormat:@"Exiting connection %@ read loop", connection];
      [connectionReadCompleted resolveWithResult:NSNull.null];
    });
    return [[FBFuture
      futureWithFutures:@[
        socketReadCompleted,
        connectionReadCompleted,
      ]]
      onQueue:self.connectionToSocketQueue notifyOfCompletion:^(id _) {
        [logger logFormat:@"Closing socket file descriptor %d", socket];
        close(socket);
      }];
  }
  return nil;
}

@end

@interface FBDeviceDebugServer () <FBSocketServerDelegate>

@property (nonatomic, strong, readonly) FBAMDServiceConnection *serviceConnection;
@property (nonatomic, strong, readonly) FBSocketServer *tcpServer;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@property (nonatomic, strong, readwrite) FBMutableFuture<NSNull *> *teardown;
@property (nonatomic, strong, nullable, readwrite) FBDeviceDebugServer_TwistedPairFiles *twistedPair;

@end

@implementation FBDeviceDebugServer

@synthesize queue = _queue;
@synthesize lldbBootstrapCommands = _lldbBootstrapCommands;

#pragma mark Initializers

+ (FBFuture<FBDeviceDebugServer *> *)debugServerForServiceConnection:(FBFutureContext<FBAMDServiceConnection *> *)service port:(in_port_t)port lldbBootstrapCommands:(NSArray<NSString *> *)lldbBootstrapCommands queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  return [[service
    onQueue:queue push:^(FBAMDServiceConnection *serviceConnection) {
      FBDeviceDebugServer *server = [[FBDeviceDebugServer alloc] initWithServiceConnection:serviceConnection port:port lldbBootstrapCommands:lldbBootstrapCommands queue:queue logger:logger];
      return [server startListening];
    }]
    onQueue:queue enter:^(FBDeviceDebugServer *server, FBMutableFuture<NSNull *> *teardown) {
      server.teardown = teardown;
      return server;
    }];
}

- (instancetype)initWithServiceConnection:(FBAMDServiceConnection *)serviceConnection port:(in_port_t)port lldbBootstrapCommands:(NSArray<NSString *> *)lldbBootstrapCommands queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _serviceConnection = serviceConnection;
  _tcpServer = [FBSocketServer socketServerOnPort:port delegate:self];
  _lldbBootstrapCommands = lldbBootstrapCommands;
  _queue = queue;
  _logger = logger;

  return self;
}

#pragma mark FBSocketReaderDelegate

- (void)socketServer:(FBSocketServer *)server clientConnected:(struct in6_addr)address fileDescriptor:(int)fileDescriptor
{
  if (self.twistedPair) {
    [self.logger log:@"Rejecting connection, we have an existing pair"];
    NSData *data = [@"$NEUnspecified#00" dataUsingEncoding:NSASCIIStringEncoding];
    write(fileDescriptor, data.bytes, data.length);
    close(fileDescriptor);
    return;
  }
  [self.logger log:@"Client connected, connecting all file handles"];
  FBDeviceDebugServer_TwistedPairFiles *twistedPair = [[FBDeviceDebugServer_TwistedPairFiles alloc] initWithSocket:fileDescriptor connection:self.serviceConnection logger:self.logger];
  NSError *error = nil;
  FBFuture<NSNull *> *completed = [twistedPair startWithError:&error];
  if (!completed) {
    [self.logger logFormat:@"Failed to start connection %@", error];
    return;
  }
  [completed onQueue:self.queue notifyOfCompletion:^(id _) {
    [self.logger log:@"Client Disconnected"];
    self.twistedPair = nil;
  }];
  [self.teardown resolveFromFuture:completed];
  self.twistedPair = twistedPair;
}

#pragma mark FBiOSTargetOperation

- (FBFuture<NSNull *> *)completed
{
  return self.teardown;
}

#pragma mark Private Methods

- (FBFutureContext<FBDeviceDebugServer *> *)startListening
{
  return [[self.tcpServer
    startListeningContext]
    onQueue:self.queue pend:^(NSNull *_) {
      [self.logger logFormat:@"TCP Server now running, boostrap commands for lldb are %@", [self.lldbBootstrapCommands componentsJoinedByString:@"\n"]];
      return [FBFuture futureWithResult:self];
    }];
}


@end
