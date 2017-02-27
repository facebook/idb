/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBBundleDescriptor.h"

#import "FBBinaryDescriptor.h"
#import "FBFileManager.h"
#import "FBControlCoreError.h"

@implementation FBBundleDescriptor

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

+ (nullable instancetype)withName:(NSString *)name path:(NSString *)path bundleID:(NSString *)bundleID binary:(FBBinaryDescriptor *)binary
{
  if (!name || !path || !bundleID) {
    return nil;
  }
  return [[self alloc] initWithName:name path:path bundleID:bundleID binary:binary];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[self.class alloc]
    initWithName:self.name
    path:self.path
    bundleID:self.bundleID
    binary:self.binary];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  NSString *name = [coder decodeObjectForKey:NSStringFromSelector(@selector(name))];
  NSString *path = [coder decodeObjectForKey:NSStringFromSelector(@selector(path))];
  NSString *bundleID = [coder decodeObjectForKey:NSStringFromSelector(@selector(bundleID))];
  FBBinaryDescriptor *binary = [coder decodeObjectForKey:NSStringFromSelector(@selector(binary))];

  return [[self.class alloc]
    initWithName:name
    path:path
    bundleID:bundleID
    binary:binary];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.name forKey:NSStringFromSelector(@selector(name))];
  [coder encodeObject:self.path forKey:NSStringFromSelector(@selector(path))];
  [coder encodeObject:self.bundleID forKey:NSStringFromSelector(@selector(bundleID))];
  [coder encodeObject:self.binary forKey:NSStringFromSelector(@selector(binary))];
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

  if(![fileManager copyItemAtPath:self.path toPath:targetBundlePath error:&innerError]) {
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

@end
