/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBIDBPortsConfiguration.h"

static NSString *const GrpcPortKey = @"-grpc-port";
static NSString *const GrpcSwiftPortEnvKey = @"IDB_SWIFT_COMPANION_PORT";

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

  _debugserverPort = [userDefaults integerForKey:@"-debug-port"] ?: 10881;
  _grpcPort = [userDefaults stringForKey:GrpcPortKey] ? [userDefaults integerForKey:GrpcPortKey] : 10882;
  _grpcSwiftPort = 0;
  
  NSString *swiftPort = [NSProcessInfo.processInfo.environment objectForKey:GrpcSwiftPortEnvKey];
  if (swiftPort.length > 0) {
    _grpcSwiftPort = [swiftPort integerValue];
  }
  _grpcDomainSocket = [userDefaults stringForKey:@"-grpc-domain-sock"];
  _tlsCertPath = [userDefaults stringForKey:@"-tls-cert-path"];

  return self;
}

@end
