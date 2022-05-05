/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBIDBPortsConfiguration.h"

@implementation FBIDBPortsConfiguration

#pragma mark Initializers


- (instancetype)initWithGrpcDomainSocket:(NSString *)grpcDomainSocket grpcPort:(in_port_t)grpcPort debugserverPort:(in_port_t)debugserverPort tlsCertPath:(NSString *)tlsCertPath {
  self = [super init];
  if (!self) {
    return nil;
  }
  _grpcDomainSocket = grpcDomainSocket;
  _grpcPort = grpcPort;
  _debugserverPort = debugserverPort;
  _tlsCertPath = tlsCertPath;
  
  return self;
}

@end
