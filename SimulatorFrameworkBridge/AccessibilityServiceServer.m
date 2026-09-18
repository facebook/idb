/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "AccessibilityServiceServer.h"

#import <arpa/inet.h>
#import <errno.h>
#import <poll.h>
#import <sys/socket.h>
#import <sys/time.h>
#import <sys/un.h>
#import <unistd.h>

#import "AccessibilityService.h"
#import "AccessibilityService+Testing.h"
#import "AccessibilityService_Private.h"
#if __has_include(<SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>)
 #import <SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>
#else
 #import "SimulatorFrameworkBridgeSupport-Swift.h"
#endif

static const uint32_t kMaxFrameBytes = 16 * 1024 * 1024;
static const int kDefaultIdleTimeoutSeconds = 300;
static const int kServeBacklog = 16;

static BOOL FBAXBridgeWriteFully(int fd, const void *buffer, size_t length)
{
  const char *bytes = buffer;
  size_t offset = 0;
  while (offset < length) {
    ssize_t written = send(fd, bytes + offset, length - offset, MSG_NOSIGNAL);
    if (written < 0) {
      if (errno == EINTR) {
        continue;
      }
      return NO;
    }
    if (written == 0) {
      return NO;
    }
    offset += (size_t)written;
  }
  return YES;
}

static BOOL FBAXBridgeReadFully(int fd, void *buffer, size_t length)
{
  char *bytes = buffer;
  size_t offset = 0;
  while (offset < length) {
    ssize_t received = recv(fd, bytes + offset, length - offset, 0);
    if (received < 0) {
      if (errno == EINTR) {
        continue;
      }
      return NO;
    }
    if (received == 0) {
      return NO;
    }
    offset += (size_t)received;
  }
  return YES;
}

static BOOL FBAXBridgeServeConnection(int connection, int idleTimeoutSeconds, FBAXBridgeSocketResponse *(^handleRequest)(NSData *))
{
  struct timeval receiveTimeout = {.tv_sec = idleTimeoutSeconds, .tv_usec = 0};
  setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, sizeof(receiveTimeout));

  while (YES) {
    @autoreleasepool {
      uint32_t frameLength = 0;
      if (!FBAXBridgeReadFully(connection, &frameLength, sizeof(frameLength))) {
        return NO;
      }
      frameLength = ntohl(frameLength);
      if (frameLength == 0 || frameLength > kMaxFrameBytes) {
        return NO;
      }

      NSMutableData *requestData = [NSMutableData dataWithLength:frameLength];
      if (!FBAXBridgeReadFully(connection, requestData.mutableBytes, frameLength)) {
        return NO;
      }

      FBAXBridgeSocketResponse *response = handleRequest(requestData);
      NSData *responseData = response.data;
      uint32_t responseLength = htonl((uint32_t)responseData.length);
      if (!FBAXBridgeWriteFully(connection, &responseLength, sizeof(responseLength))
          || !FBAXBridgeWriteFully(connection, responseData.bytes, responseData.length)) {
        return NO;
      }
      if (response.shutdown) {
        return YES;
      }
    }
  }
}

@implementation FBAXBridgeSocketResponse

- (instancetype)initWithData:(NSData *)data shutdown:(BOOL)shutdown
{
  self = [super init];
  if (self) {
    _data = [data copy];
    _shutdown = shutdown;
  }
  return self;
}

@end

@implementation FBAXBridgeServer

+ (int32_t)serveWithSocketPath:(NSString *)socketPath
            idleTimeoutSeconds:(int32_t)idleTimeoutSeconds
              exitOnDisconnect:(BOOL)exitOnDisconnect
                prepareRuntime:(void (^)(void))prepareRuntime
                 handleRequest:(FBAXBridgeSocketResponse *(^)(NSData *))handleRequest
{
  int listenFd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (listenFd < 0) {
    NSLog(@"[AccessibilityService] socket() failed: %s", strerror(errno));
    return 1;
  }

  struct sockaddr_un address;
  memset(&address, 0, sizeof(address));
  address.sun_family = AF_UNIX;
  if (strlen(socketPath.fileSystemRepresentation) >= sizeof(address.sun_path)) {
    NSLog(@"[AccessibilityService] socket path too long: %@", socketPath);
    close(listenFd);
    return 1;
  }
  strlcpy(address.sun_path, socketPath.fileSystemRepresentation, sizeof(address.sun_path));
  unlink(address.sun_path);

  if (bind(listenFd, (struct sockaddr *)&address, sizeof(address)) != 0) {
    NSLog(@"[AccessibilityService] bind(%@) failed: %s", socketPath, strerror(errno));
    close(listenFd);
    return 1;
  }
  if (listen(listenFd, kServeBacklog) != 0) {
    NSLog(@"[AccessibilityService] listen() failed: %s", strerror(errno));
    close(listenFd);
    return 1;
  }

  prepareRuntime();
  NSLog(@"[AccessibilityService] serving accessibility on %@ (idle timeout %ds)", socketPath, idleTimeoutSeconds);

  BOOL shutdownRequested = NO;
  while (!shutdownRequested) {
    struct pollfd listenPoll = {.fd = listenFd, .events = POLLIN, .revents = 0};
    int ready = poll(&listenPoll, 1, idleTimeoutSeconds * 1000);
    if (ready == 0) {
      NSLog(@"[AccessibilityService] idle %ds with no client; exiting", idleTimeoutSeconds);
      break;
    }
    if (ready < 0) {
      if (errno == EINTR) {
        continue;
      }
      break;
    }

    int connection = accept(listenFd, NULL, NULL);
    if (connection < 0) {
      if (errno == EINTR) {
        continue;
      }
      break;
    }
    shutdownRequested = FBAXBridgeServeConnection(connection, idleTimeoutSeconds, handleRequest);
    close(connection);

    if (exitOnDisconnect) {
      NSLog(@"[AccessibilityService] exclusive client disconnected; exiting");
      break;
    }
    if (shutdownRequested) {
      NSLog(@"[AccessibilityService] shutdown requested by client; exiting");
    }
  }

  close(listenFd);
  unlink(address.sun_path);
  return 0;
}

@end

int FBAXBridgeServe(NSString *socketPath, NSArray<NSString *> *arguments)
{
  return [FBAXBridgeServer serveWithSocketPath:socketPath
                            idleTimeoutSeconds:[FBAXBridgeArguments idleTimeoutWithArguments:arguments fallback:kDefaultIdleTimeoutSeconds]
                              exitOnDisconnect:[FBAXBridgeArguments exitOnDisconnectWithArguments:arguments]
                                prepareRuntime:^{ FBAXBridgePrepareRuntime(); }
                                 handleRequest:^FBAXBridgeSocketResponse *(NSData *request) {
                                   BOOL shutdown = NO;
                                   NSDictionary *response = FBAXBridgeHandleRequestData(request, &shutdown);
                                   return [[FBAXBridgeSocketResponse alloc] initWithData:FBAXBridgeSerializeResponse(response) shutdown:shutdown];
                                 }];
}

int FBAXBridgeServeBacklogForTesting(void)
{
  return kServeBacklog;
}

int FBAXBridgeIdleTimeoutForTesting(NSArray<NSString *> *arguments, int fallback)
{
  return [FBAXBridgeArguments idleTimeoutWithArguments:arguments fallback:fallback];
}

int FBAXBridgeDefaultIdleTimeoutForTesting(void)
{
  return kDefaultIdleTimeoutSeconds;
}

BOOL FBAXBridgeExitOnDisconnectForTesting(NSArray<NSString *> *arguments)
{
  return [FBAXBridgeArguments exitOnDisconnectWithArguments:arguments];
}
