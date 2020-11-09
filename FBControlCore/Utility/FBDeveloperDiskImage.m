/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeveloperDiskImage.h"

#import <FBControlCore/FBControlCore.h>

static NSInteger ScoreVersions(NSOperatingSystemVersion current, NSOperatingSystemVersion target)
{
  NSInteger major = ABS((current.majorVersion - target.majorVersion) * 10);
  NSInteger minor = ABS(current.minorVersion - target.minorVersion);
  return major + minor;
}

@implementation FBDeveloperDiskImage

#pragma mark Private

+ (NSArray<FBDeveloperDiskImage *> *)allDiskImagesFromSearchPath:(NSString *)searchPath logger:(id<FBControlCoreLogger>)logger
{
  NSMutableArray<FBDeveloperDiskImage *> *images = NSMutableArray.array;
  [logger logFormat:@"Attempting to find Disk Images at path %@", searchPath];
  for (NSString *fileName in [NSFileManager.defaultManager contentsOfDirectoryAtPath:searchPath error:nil] ?: @[]) {
    NSString *resolvedPath = [searchPath stringByAppendingPathComponent:fileName];
    NSError *error = nil;
    FBDeveloperDiskImage *image = [self diskImageAtPath:resolvedPath error:&error];
    if (!image) {
      [logger logFormat:@"%@ does not contain a valid disk image", error];
      continue;
    }
    [images addObject:image];
  }
  return images;
}

+ (nullable FBDeveloperDiskImage *)diskImageAtPath:(NSString *)path error:(NSError **)error
{
  NSString *diskImagePath = [path stringByAppendingPathComponent:@"DeveloperDiskImage.dmg"];
  if (![NSFileManager.defaultManager fileExistsAtPath:diskImagePath]) {
    return [[FBControlCoreError
      describeFormat:@"Disk image does not exist at expected path %@", diskImagePath]
      fail:error];
  }
  NSString *signaturePath = [diskImagePath stringByAppendingString:@".signature"];
  NSData *signature = [NSData dataWithContentsOfFile:signaturePath];
  if (!signature) {
    return [[FBControlCoreError
      describeFormat:@"Failed to load signature at %@", signaturePath]
      fail:error];
  }
  NSOperatingSystemVersion version = [FBOSVersion operatingSystemVersionFromName:path.lastPathComponent];
  return [[FBDeveloperDiskImage alloc] initWithDiskImagePath:diskImagePath signature:signature version:version];
}

#pragma mark Initializers

+ (FBDeveloperDiskImage *)developerDiskImage:(NSOperatingSystemVersion)targetVersion logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSArray<FBDeveloperDiskImage *> *images = FBDeveloperDiskImage.allDiskImages;
  return [self bestImageForImages:images targetVersion:targetVersion logger:logger error:error];
}

+ (NSArray<FBDeveloperDiskImage *> *)allDiskImages
{
  static dispatch_once_t onceToken;
  static NSArray<FBDeveloperDiskImage *> *images = nil;
  dispatch_once(&onceToken, ^{
    images = [self allDiskImagesFromSearchPath:[FBXcodeConfiguration.developerDirectory stringByAppendingPathComponent:@"Platforms/iPhoneOS.platform/DeviceSupport"] logger:FBControlCoreGlobalConfiguration.defaultLogger];
  });
  return images;
}

- (instancetype)initWithDiskImagePath:(NSString *)diskImagePath signature:(NSData *)signature version:(NSOperatingSystemVersion)version
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _diskImagePath = diskImagePath;
  _signature = signature;
  _version = version;

  return self;
}

#pragma mark Public

+ (NSString *)pathForDeveloperSymbols:(NSString *)buildVersion logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSArray<NSString *> *searchPaths = @[
    [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Developer/Xcode/iOS DeviceSupport"],
    [FBXcodeConfiguration.developerDirectory stringByAppendingPathComponent:@"Platforms/iPhoneOS.platform/DeviceSupport"],
  ];
  [logger logFormat:@"Attempting to find Symbols directory by build version %@", buildVersion];
  for (NSString *searchPath in searchPaths) {
    for (NSString *fileName in [NSFileManager.defaultManager enumeratorAtPath:searchPath]) {
      NSString *path = [searchPath stringByAppendingPathComponent:fileName];
      if ([path containsString:buildVersion]) {
        return [path stringByAppendingPathComponent:@"Symbols"];
      }
    }
  }
  return [[FBControlCoreError
    describeFormat:@"Could not find the Symbols for %@", self]
    fail:error];
}

+ (nullable FBDeveloperDiskImage *)bestImageForImages:(NSArray<FBDeveloperDiskImage *> *)images targetVersion:(NSOperatingSystemVersion)targetVersion logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  if (images.count == 0) {
    return [[FBControlCoreError
      describe:@"No disk images provided"]
      fail:error];
  }

  // Sort the array such that the best matching version appears at the top.
  NSArray<FBDeveloperDiskImage *> *sorted = [images sortedArrayUsingComparator:^ NSComparisonResult (FBDeveloperDiskImage *left, FBDeveloperDiskImage *right) {
    NSOperatingSystemVersion leftVersion = left.version;
    NSOperatingSystemVersion rightVersion = right.version;
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

  FBDeveloperDiskImage *best = sorted.firstObject;
  NSOperatingSystemVersion bestVersion = best.version;
  if (bestVersion.majorVersion == targetVersion.majorVersion && bestVersion.minorVersion == targetVersion.minorVersion) {
    [logger logFormat:@"Found the best match for %ld.%ld at %@", targetVersion.majorVersion, targetVersion.minorVersion, best];
    return best;
  }
  if (bestVersion.majorVersion == targetVersion.majorVersion) {
    [logger logFormat:@"Found the closest match for %ld.%ld at %@", targetVersion.majorVersion, targetVersion.minorVersion, best];
    return best;
  }
  return [[FBControlCoreError
    describeFormat:@"The best match %@ is not suitable for %ld.%ld", best, targetVersion.majorVersion, targetVersion.minorVersion]
    fail:error];
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"%@: %lu.%lu", self.diskImagePath, self.version.majorVersion, self.version.minorVersion];
}

@end
