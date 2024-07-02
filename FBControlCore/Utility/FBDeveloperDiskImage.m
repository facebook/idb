/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeveloperDiskImage.h"

#import <FBControlCore/FBControlCore.h>

static NSString *const ExtraDeviceSupportDirEnv = @"IDB_EXTRA_DEVICE_SUPPORT_DIR";

static NSInteger ScoreVersions(NSOperatingSystemVersion current, NSOperatingSystemVersion target)
{
  NSInteger major = ABS((current.majorVersion - target.majorVersion) * 10);
  NSInteger minor = ABS(current.minorVersion - target.minorVersion);
  return major + minor;
}

@implementation FBDeveloperDiskImage

#pragma mark Private

+ (NSArray<FBDeveloperDiskImage *> *)allDiskImagesFromSearchPath:(NSString *)searchPath xcodeVersion:(NSOperatingSystemVersion)xcodeVersion logger:(id<FBControlCoreLogger>)logger
{
  NSMutableArray<FBDeveloperDiskImage *> *images = NSMutableArray.array;
  [logger logFormat:@"Attempting to find Disk Images at path %@", searchPath];
  for (NSString *fileName in [NSFileManager.defaultManager contentsOfDirectoryAtPath:searchPath error:nil] ?: @[]) {
    NSString *resolvedPath = [searchPath stringByAppendingPathComponent:fileName];
    NSError *error = nil;
    FBDeveloperDiskImage *image = [self diskImageAtPath:resolvedPath xcodeVersion:xcodeVersion error:&error];
    if (!image) {
      [logger logFormat:@"%@ does not contain a valid disk image", error];
      continue;
    }
    [images addObject:image];
  }
  return [images sortedArrayUsingSelector:@selector(compare:)];
}

+ (nullable FBDeveloperDiskImage *)diskImageAtPath:(NSString *)path xcodeVersion:(NSOperatingSystemVersion)xcodeVersion error:(NSError **)error
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
  return [[FBDeveloperDiskImage alloc] initWithDiskImagePath:diskImagePath signature:signature version:version xcodeVersion:xcodeVersion];
}

#pragma mark Initializers

+ (FBDeveloperDiskImage *)developerDiskImage:(NSOperatingSystemVersion)targetVersion logger:(id<FBControlCoreLogger>)logger platformRootDirectory:(NSString*)platformRootDirectory error:(NSError **)error
{
    NSArray<FBDeveloperDiskImage *> *images = [FBDeveloperDiskImage allDiskImages:platformRootDirectory];
  return [self bestImageForImages:images targetVersion:targetVersion logger:logger error:error];
}

+ (NSArray<FBDeveloperDiskImage *> *)allDiskImages:(NSString*)platformRootDirectory
{
  static dispatch_once_t onceToken;
  static NSArray<FBDeveloperDiskImage *> *images = nil;
  dispatch_once(&onceToken, ^{
    images = [self allDiskImagesFromSearchPath:[platformRootDirectory stringByAppendingPathComponent:@"DeviceSupport"] xcodeVersion:FBXcodeConfiguration.xcodeVersion logger:FBControlCoreGlobalConfiguration.defaultLogger];
    if ([[NSProcessInfo.processInfo.environment allKeys] containsObject:ExtraDeviceSupportDirEnv]) {
      NSArray<FBDeveloperDiskImage *> *extraImages = [self allDiskImagesFromSearchPath:NSProcessInfo.processInfo.environment[ExtraDeviceSupportDirEnv] xcodeVersion:FBXcodeConfiguration.xcodeVersion logger:FBControlCoreGlobalConfiguration.defaultLogger];
      images = [images arrayByAddingObjectsFromArray:extraImages];
    }
  });
  return images;
}

+ (FBDeveloperDiskImage *) unknownDiskImageWithSignature:(NSData *)signature
{
  NSOperatingSystemVersion unknownVersion = {
    .majorVersion = 0,
    .minorVersion = 0,
    .patchVersion = 0,
  };
  return [[self alloc] initWithDiskImagePath:@"unknown.dmg" signature:signature version:unknownVersion xcodeVersion:unknownVersion];
}

- (instancetype)initWithDiskImagePath:(NSString *)diskImagePath signature:(NSData *)signature version:(NSOperatingSystemVersion)version xcodeVersion:(NSOperatingSystemVersion)xcodeVersion
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _diskImagePath = diskImagePath;
  _signature = signature;
  _version = version;
  _xcodeVersion = xcodeVersion;

  return self;
}

#pragma mark Public

// TODO: This only yields symbols for iOS, not tvOS or other.
+ (NSString *)pathForDeveloperSymbols:(NSString *)buildVersion logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSArray<NSString *> *searchPaths = @[
    [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Developer/Xcode/iOS DeviceSupport"],
    [FBXcodeConfiguration.developerDirectory stringByAppendingPathComponent:@"Platforms/iPhoneOS.platform/DeviceSupport"],
  ];
  [logger logFormat:@"Attempting to find Symbols directory by build version %@", buildVersion];
  NSMutableArray<NSString *> *paths = NSMutableArray.array;
  for (NSString *searchPath in searchPaths) {
    NSError *innerError = nil;
    NSArray<NSString *> *supportPaths = [NSFileManager.defaultManager contentsOfDirectoryAtPath:searchPath error:&innerError];
    if (!supportPaths) {
      continue;
    }
    for (NSString *supportName in supportPaths) {
      NSString *supportPath = [searchPath stringByAppendingPathComponent:supportName];
      BOOL isDirectory = NO;
      if (![NSFileManager.defaultManager fileExistsAtPath:supportPath isDirectory:&isDirectory]) {
        continue;
      }
      if (isDirectory == NO) {
        continue;
      }
      NSString *symbolsPath = [supportPath stringByAppendingPathComponent:@"Symbols"];
      if (![NSFileManager.defaultManager fileExistsAtPath:symbolsPath isDirectory:&isDirectory]) {
        continue;
      }
      if (isDirectory == NO) {
        continue;
      }
      [paths addObject:symbolsPath];
    }
  }
  for (NSString *path in paths) {
    if (![path containsString:buildVersion]) {
      continue;
    }
    return path;
  }
  return [[FBControlCoreError
    describeFormat:@"Could not find the Symbols for %@ in any of %@", buildVersion, [FBCollectionInformation oneLineDescriptionFromArray:paths]]
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

- (NSComparisonResult)compare:(FBDeveloperDiskImage *)other
{
  NSComparisonResult comparison = [@(self.version.majorVersion) compare:@(other.version.majorVersion)];
  if (comparison != NSOrderedSame) {
    return comparison;
  }
  comparison = [@(self.version.minorVersion) compare:@(other.version.minorVersion)];
  if (comparison != NSOrderedSame) {
    return comparison;
  }
  return [@(self.version.patchVersion) compare:@(other.version.patchVersion)];
}

@end
