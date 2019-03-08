/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAMDServiceConnection.h"

#import "FBDeviceControlError.h"

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

#pragma mark Public

- (NSData *)receive:(size_t)size error:(NSError **)error
{
  void *buffer = malloc(size);
  size_t readBytes = (size_t) self.calls.ServiceConnectionReceive(self.connection, buffer, size);
  if (readBytes < size) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to receive %zu bytes from AMDServiceConnectionReceive", readBytes]
      fail:error];
  }
  return [NSData dataWithBytesNoCopy:buffer length:size freeWhenDone:YES];
}

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
    return [[FBDeviceControlError
      describeFormat:@"Failed to invalidate connection %@ with error %d", connectionDescription, status]
      failBool:error];
  }
  [self.logger logFormat:@"Invalidated connection %@", connectionDescription];
  // AMDServiceConnectionInvalidate does not release the connection.
  CFRelease(_connection);
  _connection = NULL;
  return YES;
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
