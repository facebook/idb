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

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Name: %@ | Path: %@ | Architectures: %@",
    self.name,
    self.path,
    [FBCollectionInformation oneLineDescriptionFromArray:self.architectures.allObjects]
  ];
}

#pragma mark JSON Conversion

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

#pragma mark Private

+ (NSString *)binaryNameForBinaryPath:(NSString *)binaryPath
{
  return binaryPath.lastPathComponent;
}

@end
