/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeveloperDiskImage.h"

#import <FBControlCore/FBControlCore.h>

#import "FBDevice.h"
#import "FBDeviceControlError.h"

@implementation FBDeveloperDiskImage

#pragma mark Private

+ (NSString *)pathForDeveloperDiskImageDirectory:(FBDevice *)device logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSArray<NSString *> *searchPaths = @[
    [FBXcodeConfiguration.developerDirectory stringByAppendingPathComponent:@"Platforms/iPhoneOS.platform/DeviceSupport"],
  ];

  NSString *buildVersion = device.buildVersion;
  [logger logFormat:@"Attempting to find Disk Image directory by Build Version %@", buildVersion];
  for (NSString *searchPath in searchPaths) {
    for (NSString *fileName in [NSFileManager.defaultManager enumeratorAtPath:searchPath]) {
      NSString *path = [searchPath stringByAppendingPathComponent:fileName];
      if ([path containsString:buildVersion]) {
        return path;
      }
    }
  }
  NSOperatingSystemVersion targetVersion = device.operatingSystemVersion;
  [logger logFormat:@"Attempting to find Disk Image directory by Version %ld.%ld", (long)targetVersion.majorVersion, targetVersion.minorVersion];
  for (NSString *searchPath in searchPaths) {
    for (NSString *fileName in [NSFileManager.defaultManager enumeratorAtPath:searchPath]) {
      NSOperatingSystemVersion currentVersion = [FBDevice operatingSystemVersionFromString:fileName];
      if (currentVersion.majorVersion == targetVersion.majorVersion && currentVersion.minorVersion == targetVersion.minorVersion) {
        return [searchPath stringByAppendingPathComponent:fileName];
      }
    }
  }

  return [[FBDeviceControlError
    describeFormat:@"Could not find the DeveloperDiskImage for %@", self]
    fail:error];
}

#pragma mark Initializers

+ (FBDeveloperDiskImage *)developerDiskImage:(FBDevice *)device logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSString *directory = [self pathForDeveloperDiskImageDirectory:device logger:logger error:error];
  if (!directory) {
    return nil;
  }
  NSString *diskImagePath = [directory stringByAppendingPathComponent:@"DeveloperDiskImage.dmg"];
  if (![NSFileManager.defaultManager fileExistsAtPath:diskImagePath]) {
    return [[FBDeviceControlError
      describeFormat:@"Disk image does not exist at expected path %@", diskImagePath]
      fail:error];
  }
  NSString *signaturePath = [diskImagePath stringByAppendingString:@".signature"];
  NSData *signature = [NSData dataWithContentsOfFile:signaturePath];
  if (!signature) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to load signature at %@", signaturePath]
      fail:error];
  }
  return [[FBDeveloperDiskImage alloc] initWithDiskImagePath:diskImagePath signature:signature];
}

- (instancetype)initWithDiskImagePath:(NSString *)diskImagePath signature:(NSData *)signature
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _diskImagePath = diskImagePath;
  _signature = signature;

  return self;
}

#pragma mark Public

+ (NSString *)pathForDeveloperSymbols:(FBDevice *)device logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSArray<NSString *> *searchPaths = @[
    [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Developer/Xcode/iOS DeviceSupport"],
    [FBXcodeConfiguration.developerDirectory stringByAppendingPathComponent:@"Platforms/iPhoneOS.platform/DeviceSupport"],
  ];
  NSString *buildVersion = device.buildVersion;
  [logger logFormat:@"Attempting to find Symbols directory by build version %@", buildVersion];
  for (NSString *searchPath in searchPaths) {
    for (NSString *fileName in [NSFileManager.defaultManager enumeratorAtPath:searchPath]) {
      NSString *path = [searchPath stringByAppendingPathComponent:fileName];
      if ([path containsString:buildVersion]) {
        return [path stringByAppendingPathComponent:@"Symbols"];
      }
    }
  }
  return [[FBDeviceControlError
    describeFormat:@"Could not find the Symbols for %@", self]
    fail:error];
}


@end
