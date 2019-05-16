/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBBundleDescriptor.h"

#import "FBBinaryDescriptor.h"
#import "FBFileManager.h"
#import "FBControlCoreError.h"
#import "FBCollectionInformation.h"

@implementation FBBundleDescriptor

#pragma mark Initializers

- (instancetype)initWithName:(NSString *)name path:(NSString *)path bundleID:(NSString *)bundleID binary:(nullable FBBinaryDescriptor *)binary
{
  NSParameterAssert(name);
  NSParameterAssert(path);
  NSParameterAssert(bundleID);

  self = [super init];
  if (!self) {
    return nil;
  }

  _name = name;
  _path = path;
  _bundleID = bundleID;
  _binary = binary;

  return self;
}

+ (nullable instancetype)bundleFromPath:(NSString *)path error:(NSError **)error
{
  if (!path) {
    return [[FBControlCoreError
      describe:@"Nil file path provided for bundle path"]
      fail:error];
  }
  NSString *bundleName = [self bundleNameForPath:path];
  if (!bundleName) {
    return [[FBControlCoreError
      describeFormat:@"Could not obtain bundle name for path %@", path]
      fail:error];
  }
  NSError *innerError = nil;
  NSString *bundleID = [self infoPlistKey:@"CFBundleIdentifier" forBundleAtPath:path error:&innerError];
  if (!bundleID) {
    return [[FBControlCoreError
      describeFormat:@"Could not obtain Bundle ID for bundle at path %@: %@", path, innerError]
      fail:error];
  }
  FBBinaryDescriptor *binary = [self binaryForBundlePath:path error:&innerError];
  if (!binary) {
    return [[[FBControlCoreError describeFormat:@"Could not obtain binary for bundle at path %@", path] causedBy:innerError] fail:error];
  }
  return [[self alloc] initWithName:bundleName path:path bundleID:bundleID binary:binary];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  // Is immutable
  return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBBundleDescriptor *)object
{
  if (![object isMemberOfClass:self.class]) {
    return NO;
  }
  return [object.name isEqual:self.name] &&
         [object.path isEqual:self.path] &&
         [object.bundleID isEqual:self.bundleID] &&
         [object.binary isEqual:self.binary];
}

- (NSUInteger)hash
{
  return self.name.hash | self.path.hash | self.bundleID.hash | self.binary.hash;
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [self shortDescription];
}

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:
    @"Name: %@ | ID: %@",
    self.name,
    self.bundleID
  ];
}

- (NSString *)debugDescription
{
  return [NSString stringWithFormat:
    @"%@ | Path: %@ | Binary (%@)",
    self.shortDescription,
    self.path,
    self.binary
  ];
}

#pragma mark FBJSONSerializable

- (NSDictionary *)jsonSerializableRepresentation
{
  NSMutableDictionary *result = [[NSMutableDictionary alloc] init];

  result[@"name"] = self.name;
  result[@"bundle_id"] = self.bundleID;
  result[@"path"] = self.path;
  if (self.binary) {
    result[@"binary"] = self.binary.jsonSerializableRepresentation;
  }

  return result;
}

#pragma mark Public Methods

- (nullable instancetype)relocateBundleIntoDirectory:(NSString *)destinationDirectory fileManager:(id<FBFileManager>)fileManager error:(NSError **)error
{
  NSParameterAssert(destinationDirectory);
  NSParameterAssert(fileManager);

  NSError *innerError = nil;
  NSString *bundleName = self.path.lastPathComponent;

  if (![fileManager fileExistsAtPath:destinationDirectory] && ![fileManager createDirectoryAtPath:destinationDirectory withIntermediateDirectories:YES attributes:nil error:&innerError]) {
    return [[FBControlCoreError
      describeFormat:@"Could not create destination directory at  '%@'", destinationDirectory]
      fail:error];
  }

  NSString *targetBundlePath = [destinationDirectory stringByAppendingPathComponent:bundleName];
  if ([fileManager fileExistsAtPath:targetBundlePath] && ![fileManager removeItemAtPath:targetBundlePath error:&innerError]) {
    return [[[FBControlCoreError
      describeFormat:@"Could not destination item at path '%@'", targetBundlePath]
      causedBy:innerError]
      fail:error];
  }

  if (![fileManager copyItemAtPath:self.path toPath:targetBundlePath error:&innerError]) {
    return [[[FBControlCoreError
      describeFormat:@"Could not move from '%@' to '%@'", self.path, targetBundlePath]
      causedBy:innerError]
      fail:error];
  }

  return [[self.class alloc]
    initWithName:self.name
    path:targetBundlePath
    bundleID:self.bundleID
    binary:self.binary];
}

#pragma mark Private

+ (FBBinaryDescriptor *)binaryForBundlePath:(NSString *)bundlePath error:(NSError **)error
{
  NSError *innerError = nil;
  NSString *binaryPath = [self binaryPathForBundleAtPath:bundlePath error:&innerError];
  if (!binaryPath) {
    return [[FBControlCoreError
      describeFormat:@"Could not obtain binary path for bundle path %@: %@", bundlePath, innerError]
      fail:error];
  }

  FBBinaryDescriptor *binary = [FBBinaryDescriptor binaryWithPath:binaryPath error:&innerError];
  if (!binary) {
    return [[[FBControlCoreError
      describeFormat:@"Could not obtain binary info for binary at path %@", binaryPath]
      causedBy:innerError]
      fail:error];
  }
  return binary;
}

+ (NSString *)bundleNameForPath:(NSString *)bundlePath
{
  return [self infoPlistKey:@"CFBundleName" forBundleAtPath:bundlePath error:nil] ?: bundlePath.lastPathComponent.stringByDeletingPathExtension;
}

+ (NSString *)binaryPathForBundleAtPath:(NSString *)bundlePath error:(NSError **)error
{
  NSString *binaryName = [self infoPlistKey:@"CFBundleExecutable" forBundleAtPath:bundlePath error:error];
  if (!binaryName) {
    return nil;
  }
  NSArray<NSString *> *paths = @[
    [bundlePath stringByAppendingPathComponent:binaryName],
    [[bundlePath stringByAppendingPathComponent:@"Contents/MacOS"] stringByAppendingPathComponent:binaryName]
  ];

  for (NSString *path in paths) {
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
      return path;
    }
  }
  return nil;
}

+ (NSString *)infoPlistKey:(NSString *)key forBundleAtPath:(NSString *)bundlePath error:(NSError **)error
{
  NSString *infoPlistPath = [self infoPlistPathForBundleAtPath:bundlePath error:error];
  if (!infoPlistPath) {
    return nil;
  }
  NSDictionary<NSString *, NSString *> *infoPlist = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
  if (!infoPlist) {
    return [[[FBControlCoreError
      describeFormat:@"Could not load Info.plist at path %@", infoPlistPath]
      noLogging]
      fail:error];
  }
  NSString *value = infoPlist[key];
  if (!value) {
    return [[[FBControlCoreError
      describeFormat:@"Could not load key %@ in Info.plist, values %@", key, [FBCollectionInformation oneLineDescriptionFromArray:infoPlist.allKeys]]
      noLogging]
      fail:error];
  }
  return value;
}

+ (NSString *)infoPlistPathForBundleAtPath:(NSString *)bundlePath error:(NSError **)error
{
  NSArray<NSString *> *searchPaths = @[
    bundlePath,
    [bundlePath stringByAppendingPathComponent:@"Contents"]
  ];
  NSArray<NSString *> *plists = @[
    @"info.plist",
    @"Info.plist"
  ];

  for (NSString *searchPath in searchPaths) {
    for (NSString *plist in plists) {
      NSString *path = [searchPath stringByAppendingPathComponent:plist];
      if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
        return path;
      }
    }
  }

  BOOL isDirectory = NO;
  if (![NSFileManager.defaultManager fileExistsAtPath:bundlePath isDirectory:&isDirectory]) {
    return [[[FBControlCoreError
      describeFormat:@"No Info.plist could be found as %@ does not exist", bundlePath]
      noLogging]
      fail:error];
  }
  if (!isDirectory) {
    return [[[FBControlCoreError
      describeFormat:@"No Info.plist could be found in %@ as it's not an bundle path, which must be a directory", bundlePath]
      noLogging]
      fail:error];
  }
  NSMutableArray<NSString *> *allPaths = NSMutableArray.array;
  for (NSString *searchPath in searchPaths) {
    NSArray<NSString *> *contents = [NSFileManager.defaultManager contentsOfDirectoryAtPath:searchPath error:nil];
    if (!contents) {
      continue;
    }
    [allPaths addObjectsFromArray:contents];
  }

  return [[[FBControlCoreError
    describeFormat:@"Could not find an Info.plist at any of the expected locations %@, files that do exist %@", [FBCollectionInformation oneLineDescriptionFromArray:searchPaths], [FBCollectionInformation oneLineDescriptionFromArray:allPaths]]
    noLogging]
    fail:error];
}


@end
