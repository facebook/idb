/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBIDBPortsConfiguration.h"

@implementation FBIDBPortsConfiguration

#pragma mark Initializers

+ (instancetype)portsWithArguments:(NSUserDefaults *)userDefaults
{
  return [[self alloc] initWithUserDefaults:userDefaults];
}

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _userDefaults = userDefaults;

  return self;
}

#pragma mark Properties

- (in_port_t)debugserverPort
{
  return [self.userDefaults integerForKey:@"-debug-port"] ?: 10881;
}

- (in_port_t)grpcPort
{
  return [self.userDefaults integerForKey:@"-grpc-port"] ?: 10882;
}


@end
