/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBAMDServiceConnection.h"

#import "FBDeviceControlError.h"

@implementation FBAMDServiceConnection

#pragma mark Initializers

- (instancetype)initWithServiceConnection:(AMDServiceConnectionRef)connection calls:(AMDCalls)calls
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _connection = connection;
  _calls = calls;

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
