/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeveloperDiskImage.h"

#import <FBControlCore/FBControlCore.h>

#import "FBDevice.h"
#import "FBDeviceControlError.h"

static NSInteger ScoreVersions(NSOperatingSystemVersion current, NSOperatingSystemVersion target)
{
  NSInteger major = ABS((current.majorVersion - target.majorVersion) * 10);
  NSInteger minor = ABS(current.minorVersion - target.minorVersion);
  return major + minor;
}

@implementation FBDeveloperDiskImage

#pragma mark Private

+ (NSString *)pathForDeveloperDiskImageDirectory:(id<FBDeviceCommands>)device logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
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
  // Construct all of the versions in an array
  NSOperatingSystemVersion targetVersion = [FBOSVersion operatingSystemVersionFromName:device.productVersion];
  NSMutableArray<NSString *> *resolvedPaths = NSMutableArray.array;
  [logger logFormat:@"Attempting to find Disk Image directory by Version %ld.%ld", targetVersion.majorVersion, targetVersion.minorVersion];
  for (NSString *searchPath in searchPaths) {
    for (NSString *fileName in [NSFileManager.defaultManager contentsOfDirectoryAtPath:searchPath error:nil] ?: @[]) {
      NSString *resolvedPath = [searchPath stringByAppendingPathComponent:fileName];
      [resolvedPaths addObject:resolvedPath];
    }
  }
  // Sort the array such that the best matching version appears at the top.
  [resolvedPaths sortUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
    NSOperatingSystemVersion leftVersion = [FBOSVersion operatingSystemVersionFromName:left.lastPathComponent];
    NSOperatingSystemVersion rightVersion = [FBOSVersion operatingSystemVersionFromName:right.lastPathComponent];
    NSInteger leftDelta = ScoreVersions(leftVersion, targetVersion);
    NSInteger rightDelta = ScoreVersions(rightVersion, targetVersion);
    if (leftDelta < rightDelta) {
      return NSOrderedAscending;
    }
    if (leftDelta > rightDelta) {
      return NSOrderedDescending;
    }
    return NSOrderedSame;
  }];

  NSString *best = resolvedPaths.firstObject;
  if (!best) {
    return [[FBDeviceControlError
      describeFormat:@"Could not find any DeveloperDiskImage in %@ (Build %@, Version %ld.%ld)", [FBCollectionInformation oneLineDescriptionFromArray:searchPaths], buildVersion, targetVersion.majorVersion, targetVersion.minorVersion]
      fail:error];
  }
  NSOperatingSystemVersion bestVersion = [FBOSVersion operatingSystemVersionFromName:best.lastPathComponent];
  if (bestVersion.majorVersion == targetVersion.majorVersion && bestVersion.minorVersion == targetVersion.minorVersion) {
    [logger logFormat:@"Found the best match for %ld.%ld at %@", targetVersion.majorVersion, targetVersion.minorVersion, best];
    return best;
  }
  if (bestVersion.majorVersion == targetVersion.majorVersion) {
    [logger logFormat:@"Found the closest match for %ld.%ld at %@", targetVersion.majorVersion, targetVersion.minorVersion, best];
    return best;
  }
  return [[FBDeviceControlError
    describeFormat:@"Could not find the DeveloperDiskImage in %@ (Build %@, Version %ld.%ld)", [FBCollectionInformation oneLineDescriptionFromArray:searchPaths], buildVersion, targetVersion.majorVersion, targetVersion.minorVersion]
    fail:error];
}

#pragma mark Initializers

+ (FBDeveloperDiskImage *)developerDiskImage:(id<FBDeviceCommands>)device logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
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

+ (NSString *)pathForDeveloperSymbols:(id<FBDeviceCommands>)device logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
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
