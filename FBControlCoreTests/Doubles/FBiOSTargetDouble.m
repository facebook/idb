/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBiOSTargetDouble.h"

@implementation FBiOSTargetDouble

@synthesize deviceOperator;

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [self debugDescription];
}

- (NSString *)debugDescription
{
  return [FBiOSTargetFormat.fullFormat format:self];
}

- (NSString *)shortDescription
{
  return [FBiOSTargetFormat.defaultFormat format:self];
}

- (NSComparisonResult)compare:(id<FBiOSTarget>)target
{
  return FBiOSTargetComparison(self, target);
}

#pragma mark FBJSONSerializable

- (NSDictionary *)jsonSerializableRepresentation
{
  return [FBiOSTargetFormat.fullFormat extractFrom:self];
}

#pragma mark Protocol Inheritance

- (BOOL)installApplicationWithPath:(NSString *)path error:(NSError **)error
{
  return NO;
}

- (BOOL)uninstallApplicationWithBundleID:(NSString *)bundleId error:(NSError **)error
{
  return NO;
}

- (BOOL)isApplicationInstalledWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  return NO;
}

- (BOOL)launchApplication:(FBApplicationLaunchConfiguration *)configuration error:(NSError **)error
{
  return NO;
}

- (BOOL)killApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  return NO;
}

- (BOOL)startRecordingWithError:(NSError **)error
{
  return NO;
}

- (BOOL)stopRecordingWithError:(NSError **)error
{
  return NO;
}

- (NSArray<FBApplicationDescriptor *> *)installedApplications
{
  return nil;
}

@end
