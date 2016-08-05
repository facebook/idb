/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBBinaryDescriptor.h"

#import "FBControlCoreError.h"
#import "FBCollectionInformation.h"
#import "FBBinaryParser.h"
#import "FBControlCoreGlobalConfiguration.h"

@implementation FBBinaryDescriptor

- (instancetype)initWithName:(NSString *)name path:(NSString *)path architectures:(NSSet *)architectures
{
  NSParameterAssert(name);
  NSParameterAssert(path);
  NSParameterAssert(architectures);

  self = [super init];
  if (!self) {
    return nil;
  }

  _name = name;
  _path = path;
  _architectures = architectures;

  return self;
}

+ (nullable instancetype)withName:(NSString *)name path:(NSString *)path architectures:(NSSet *)architectures
{
  if (!name || !path || !architectures) {
    return nil;
  }
  return [[self alloc] initWithName:name path:path architectures:architectures];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return [[FBBinaryDescriptor alloc] initWithName:self.name path:self.path architectures:self.architectures];
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _name = [coder decodeObjectForKey:NSStringFromSelector(@selector(name))];
  _path = [coder decodeObjectForKey:NSStringFromSelector(@selector(path))];
  _architectures = [coder decodeObjectForKey:NSStringFromSelector(@selector(architectures))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.name forKey:NSStringFromSelector(@selector(name))];
  [coder encodeObject:self.path forKey:NSStringFromSelector(@selector(path))];
  [coder encodeObject:self.architectures forKey:NSStringFromSelector(@selector(architectures))];
}

#pragma mark NSObject

- (BOOL)isEqual:(FBBinaryDescriptor *)object
{
  if (![object isMemberOfClass:self.class]) {
    return NO;
  }
  return [object.name isEqual:self.name] &&
  [object.path isEqual:self.path] &&
  [object.architectures isEqual:self.architectures];
}

- (NSUInteger)hash
{
  return self.name.hash | self.path.hash | self.architectures.hash;
}

#pragma mark - FBJSONDeserializable

+ (FBBinaryDescriptor *)inflateFromJSON:(id)json error:(NSError **)error
{
  NSString *path = json[@"path"];
  if (![path isKindOfClass:NSString.class]) {
    return [[FBControlCoreError describeFormat:@"%@ is not a valid binary path", path] fail:error];
  }
  NSError *innerError = nil;
  FBBinaryDescriptor *binary = [FBBinaryDescriptor binaryWithPath:path error:&innerError];
  if (!binary) {
    return [[[FBControlCoreError
      describeFormat:@"Could not create binary from path %@", path]
      causedBy:innerError]
      fail:error];
  }
  return binary;
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Name: %@ | Path: %@ | Architectures: %@",
    self.name,
    self.path,
    [FBCollectionInformation oneLineDescriptionFromArray:self.architectures.allObjects]
  ];
}

- (NSString *)shortDescription
{
  return [self description];
}

- (NSString *)debugDescription
{
  return [self description];
}

#pragma mark FBJSONSerializable

- (NSDictionary *)jsonSerializableRepresentation
{
  return @{
    @"name" : self.name,
    @"path" : self.path,
    @"architectures" : self.architectures.allObjects,
  };
}

@end

@implementation FBBinaryDescriptor (Helpers)

+ (nullable instancetype)binaryWithPath:(NSString *)binaryPath error:(NSError **)error;
{
  NSError *innerError = nil;
  if (![NSFileManager.defaultManager fileExistsAtPath:binaryPath]) {
    return [[FBControlCoreError
      describeFormat:@"Binary does not exist at path %@", binaryPath]
      fail:error];
  }

  NSSet *archs = [FBBinaryParser architecturesForBinaryAtPath:binaryPath error:&innerError];
  if (archs.count < 1) {
    return [FBControlCoreError failWithError:innerError errorOut:error];
  }

  return [FBBinaryDescriptor
    withName:[self binaryNameForBinaryPath:binaryPath]
    path:binaryPath
    architectures:archs];
}

+ (instancetype)launchCtl
{
  NSError *error = nil;
  FBBinaryDescriptor *binary = [FBBinaryDescriptor binaryWithPath:self.pathForiPhoneLaunchCtl error:&error];
  NSAssert(binary, @"Failed to construct launchctl binary with error %@", error);
  return binary;
}

#pragma mark Private

+ (NSString *)pathForiPhoneLaunchCtl
{
  return [FBControlCoreGlobalConfiguration.developerDirectory
    stringByAppendingPathComponent:@"/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/bin/launchctl"];
}

+ (NSString *)binaryNameForBinaryPath:(NSString *)binaryPath
{
  return binaryPath.lastPathComponent;
}

@end
