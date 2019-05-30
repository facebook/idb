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

- (instancetype)initWithName:(NSString *)name identifier:(NSString *)identifier path:(NSString *)path binary:(nullable FBBinaryDescriptor *)binary
{
  NSParameterAssert(name);
  NSParameterAssert(path);
  NSParameterAssert(identifier);

  self = [super init];
  if (!self) {
    return nil;
  }

  _name = name;
  _identifier = identifier;
  _path = path;
  _binary = binary;

  return self;
}

+ (instancetype)bundleFromPath:(NSString *)path error:(NSError **)error
{
  return [self bundleFromPath:path fallbackIdentifier:NO error:error];
}

+ (instancetype)bundleWithFallbackIdentifierFromPath:(NSString *)path error:(NSError **)error
{
  return [self bundleFromPath:path fallbackIdentifier:YES error:error];
}

+ (instancetype)bundleFromPath:(NSString *)path fallbackIdentifier:(BOOL)fallbackIdentifier error:(NSError **)error
{
  if (!path) {
    return [[FBControlCoreError
      describe:@"Nil file path provided for bundle path"]
      fail:error];
  }
  NSBundle *bundle = [NSBundle bundleWithPath:path];
  if (!bundle) {
    return [[FBControlCoreError
      describeFormat:@"Failed to load bundle at path %@", path]
      fail:error];
  }
  NSString *bundleName = [self bundleNameForBundle:bundle];
  NSString *identifier = [bundle bundleIdentifier];
  if (!identifier) {
    if (!fallbackIdentifier) {
      return [[FBControlCoreError
        describeFormat:@"Could not obtain Bundle ID for bundle at path %@", path]
        fail:error];
    }
    identifier = bundleName;
  }
  FBBinaryDescriptor *binary = [self binaryForBundle:bundle error:error];
  if (!binary) {
    return nil;
  }
  return [[self alloc] initWithName:bundleName identifier:identifier path:path binary:binary];
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
         [object.identifier isEqual:self.identifier] &&
         [object.binary isEqual:self.binary];
}

- (NSUInteger)hash
{
  return self.name.hash | self.path.hash | self.identifier.hash | self.binary.hash;
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
    self.identifier
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
  result[@"bundle_id"] = self.identifier;
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
    identifier:self.identifier
    path:targetBundlePath
    binary:self.binary];
}

#pragma mark Private

+ (FBBinaryDescriptor *)binaryForBundle:(NSBundle *)bundle error:(NSError **)error
{
  NSString *binaryPath = [bundle executablePath];
  if (!binaryPath) {
    return [[FBControlCoreError
      describeFormat:@"Could not obtain binary path for bundle %@", bundle.bundlePath]
      fail:error];
  }

  return [FBBinaryDescriptor binaryWithPath:binaryPath error:error];
}

+ (NSString *)bundleNameForBundle:(NSBundle *)bundle
{
  return bundle.infoDictionary[@"CFBundleName"] ?: bundle.infoDictionary[@"CFBundleExecutable"] ?: bundle.bundlePath.stringByDeletingPathExtension.lastPathComponent;
}

@end
