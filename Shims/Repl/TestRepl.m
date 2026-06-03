/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "TestRepl.h"

#import <dlfcn.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>

// Environment variable through which the REPL driver passes the Unix-domain
// socket path this shim should bind to. idb_companion sets it on the test
// process when launching the bundle in REPL mode. When it is absent the shim
// does nothing, so running TestRepl/start outside of a REPL session is a no-op.
static NSString *const IDBReplSocketPathEnv = @"IDB_REPL_SOCKET_PATH";

@implementation TestRepl

- (void)start
{
  NSString *socketPath = [[[NSProcessInfo processInfo] environment] objectForKey:IDBReplSocketPathEnv];
  if (socketPath.length == 0) {
    return;
  }

  int serverFd = [self _createSocketAtPath:socketPath];
  if (serverFd < 0) {
    return;
  }

  // Accept a connection and process dylib commands until the connection closes
  int clientFd = accept(serverFd, NULL, NULL);
  if (clientFd >= 0) {
    NSString *line;
    while ((line = [self _readLineFromFd:clientFd]) != nil) {
      NSDictionary *response = [self _processCommand:line];
      [self _sendResponse:response toFd:clientFd];
      [line release];
    }
    close(clientFd);
  }

  close(serverFd);
  unlink(socketPath.fileSystemRepresentation);
}

// MARK: - Socket Setup

- (int)_createSocketAtPath:(NSString *)socketPath
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

- (NSDictionary *)_processCommand:(NSString *)line
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

- (NSString *)_readLineFromFd:(int)fd
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

- (void)_sendResponse:(NSDictionary *)response toFd:(int)fd
{
  NSData *data = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
  if (!data) {
    return;
  }
  NSMutableData *lineData = [data mutableCopy];
  const char newline = '\n';
  [lineData appendBytes:&newline length:1];
  write(fd, lineData.bytes, lineData.length);
}

@end
