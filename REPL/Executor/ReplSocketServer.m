/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "ReplSocketServer.h"

#import <dlfcn.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>

// The single accepted client connection's fd, stashed for that connection's
// lifetime so injected code can issue nested host commands (see
// FBReplInvokeHostCommand). Safe as a file-scoped static: there is exactly one
// connection and the protocol is single-threaded and lockstep.
static int gClientFd = -1;

// MARK: - Socket Setup

static int CreateSocketAtPath(NSString *socketPath)
{
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    return -1;
  }

  unlink(socketPath.fileSystemRepresentation);

  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strlcpy(addr.sun_path, socketPath.fileSystemRepresentation, sizeof(addr.sun_path));

  if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0
      || listen(fd, 1) < 0) {
    close(fd);
    return -1;
  }

  return fd;
}

// MARK: - Command Processing

static NSDictionary *ProcessCommand(NSString *line)
{
  NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *command = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (!command) {
    return @{@"success" : @NO, @"error" : @"Invalid JSON"};
  }

  NSString *dylibPath = command[@"dylib"];
  NSString *symbol = command[@"symbol"];
  if (!dylibPath || !symbol) {
    return @{@"success" : @NO, @"error" : @"Missing dylib or symbol"};
  }

  void *handle = dlopen(dylibPath.fileSystemRepresentation, RTLD_NOW);
  if (!handle) {
    const char *err = dlerror();
    return @{@"success" : @NO, @"error" : [NSString stringWithUTF8String:err ?: "dlopen failed"]};
  }

  const char *(*func)(void) = (const char *(*)(void))dlsym(handle, symbol.UTF8String);
  if (!func) {
    const char *err = dlerror();
    return @{@"success" : @NO, @"error" : [NSString stringWithUTF8String:err ?: "symbol not found"]};
  }

  const char *cResult = func();
  NSString *resultStr = cResult ? [NSString stringWithUTF8String:cResult] : @"";
  free((void *)cResult);

  return @{@"success" : @YES, @"result" : resultStr};
}

// MARK: - Socket I/O

static NSString *ReadLineFromFd(int fd)
{
  NSMutableData *lineData = [NSMutableData data];
  char byte;
  while (YES) {
    ssize_t n = read(fd, &byte, 1);
    if (n <= 0) {
      return lineData.length > 0 ? [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding] : nil;
    }
    if (byte == '\n') {
      return [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
    }
    [lineData appendBytes:&byte length:1];
  }
}

static void SendResponse(NSDictionary *response, int fd)
{
  NSData *data = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
  if (!data) {
    return;
  }
  NSMutableData *lineData = [data mutableCopy];
  const char newline = '\n';
  [lineData appendBytes:&newline length:1];
  write(fd, lineData.bytes, lineData.length);
  [lineData release];
}

// MARK: - Entry Point

int FBReplServeSocket(NSString *socketPath, NSArray<NSString *> *generatedInterfaces)
{
  if (socketPath.length == 0) {
    return 0;
  }

  int serverFd = CreateSocketAtPath(socketPath);
  if (serverFd < 0) {
    return 1;
  }

  // Accept a connection and process commands until the connection closes.
  int clientFd = accept(serverFd, NULL, NULL);
  if (clientFd >= 0) {
    gClientFd = clientFd;
    // Greet the client with the .swiftinterface paths the probe generated (an
    // empty list when there are none), then handle commands.
    SendResponse(@{@"type" : @"greeting", @"interfaces" : generatedInterfaces ?: @[]}, clientFd);
    NSString *line;
    while ((line = ReadLineFromFd(clientFd)) != nil) {
      NSMutableDictionary *response = [ProcessCommand(line) mutableCopy];
      response[@"type"] = @"result";
      SendResponse(response, clientFd);
      [response release];
      [line release];
    }
    gClientFd = -1;
    close(clientFd);
  }

  close(serverFd);
  unlink(socketPath.fileSystemRepresentation);
  return 0;
}

// MARK: - Host Commands

// `used` + default visibility: nothing in the host links against this symbol
// statically -- it is resolved only via dlsym() from injected REPL dylibs -- so
// without these attributes the linker dead-strips it out of the bridge/shim and
// the lookup fails.
__attribute__((used, visibility("default")))
const char *FBReplInvokeHostCommand(const char *name, const char *argsJSON)
{
  int fd = gClientFd;
  if (fd < 0 || name == NULL) {
    return NULL;
  }

  // Parse the args JSON object if provided; default to an empty object.
  id args = @{};
  if (argsJSON != NULL) {
    NSData *argsData = [[NSString stringWithUTF8String:argsJSON] dataUsingEncoding:NSUTF8StringEncoding];
    id parsed = argsData ? [NSJSONSerialization JSONObjectWithData:argsData options:0 error:nil] : nil;
    if (parsed != nil) {
      args = parsed;
    }
  }

  SendResponse(
    @{@"type" : @"host_command",
      @"name" : [NSString stringWithUTF8String:name],
      @"args" : args},
    fd
  );

  // Read messages until the matching host_result. Because host commands are
  // strictly nested inside an executing command, nothing else is on the socket.
  NSString *line;
  while ((line = ReadLineFromFd(fd)) != nil) {
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *response = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if ([response[@"type"] isEqualToString:@"host_result"]) {
      char *result = strdup(line.UTF8String);
      [line release];
      return result;
    }
    [line release];
  }
  return NULL;
}
