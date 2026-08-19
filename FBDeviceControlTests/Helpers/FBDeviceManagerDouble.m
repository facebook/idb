/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceManagerDouble.h"

@implementation FBDeviceManagerDouble

- (BOOL)startListeningWithError:(NSError **)error
{
  return YES;
}

- (BOOL)stopListeningWithError:(NSError **)error
{
  return YES;
}

- (NSObject *)constructPublic:(PrivateDevice)privateDevice identifier:(NSString *)identifier info:(NSDictionary<NSString *, id> *)info
{
  return [NSObject new];
}

+ (void)updatePublicReference:(NSObject *)publicDevice privateDevice:(PrivateDevice)privateDevice identifier:(NSString *)identifier info:(NSDictionary<NSString *, id> *)info
{}

+ (PrivateDevice)extractPrivateReference:(NSObject *)publicDevice
{
  return NULL;
}

@end
