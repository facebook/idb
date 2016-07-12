/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulator+Connection.h"

#import "FBSimulator+Private.h"
#import "FBSimulatorEventRelay.h"
#import "FBSimulatorError.h"
#import "FBSimulatorConnection.h"

@implementation FBSimulator (Connection)

- (nullable FBSimulatorConnection *)connectWithError:(NSError **)error
{
  if (self.eventRelay.connection) {
    return self.eventRelay.connection;
  }
  if (self.state != FBSimulatorStateBooted) {
    return [[[FBSimulatorError
      describeFormat:@"Cannot connect to Simulator in state %@", self.stateString]
      inSimulator:self]
      fail:error];
  }

  FBSimulatorConnection *connection = [[FBSimulatorConnection alloc] initWithSimulator:self framebuffer:nil hid:nil];
  [self.eventSink connectionDidConnect:connection];
  return connection;
}

- (BOOL)disconnectWithTimeout:(NSTimeInterval)timeout logger:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error
{
  FBSimulatorConnection *connection = self.eventRelay.connection;
  if (!connection) {
    [logger.debug logFormat:@"Simulator %@ does not have an active connection", self.shortDescription];
    return YES;
  }

  [logger.debug logFormat:@"Simulator %@ has a connection %@, stopping & wait with timeout %f", self.shortDescription, connection, timeout];
  NSDate *date = NSDate.date;
  if (![connection terminateWithTimeout:timeout]) {
    return [[[[FBSimulatorError
      describeFormat:@"Simulator connection %@ did not teardown in less than %f seconds", connection, timeout]
      inSimulator:self]
      logger:logger]
      failBool:error];
  }
  [logger.debug logFormat:@"Simulator connection %@ torn down in %f seconds", connection, [NSDate.date timeIntervalSinceDate:date]];
  return YES;
}

@end
