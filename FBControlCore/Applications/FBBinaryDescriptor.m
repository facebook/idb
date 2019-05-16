/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBBinaryDescriptor.h"

#import "FBControlCoreError.h"
#import "FBCollectionInformation.h"
#import "FBBinaryParser.h"
#import "FBControlCoreGlobalConfiguration.h"

@implementation FBBinaryDescriptor

- (instancetype)initWithName:(NSString *)name architectures:(NSSet<FBBinaryArchitecture> *)architectures path:(NSString *)path
{
  NSParameterAssert(name);
  NSParameterAssert(architectures);
  NSParameterAssert(path);

  self = [super init];
  if (!self) {
    return nil;
  }

  _name = name;
  _architectures = architectures;
  _path = path;

  return self;
}

+ (nullable instancetype)binaryWithPath:(NSString *)binaryPath error:(NSError **)error;
{
  NSError *innerError = nil;
  if (![NSFileManager.defaultManager fileExistsAtPath:binaryPath]) {
    return [[FBControlCoreError
      describeFormat:@"Binary does not exist at path %@", binaryPath]
      fail:error];
  }

  NSSet<FBBinaryArchitecture> *archs = [FBBinaryParser architecturesForBinaryAtPath:binaryPath error:&innerError];
  if (archs.count < 1) {
    return [FBControlCoreError failWithError:innerError errorOut:error];
  }

  return [[FBBinaryDescriptor alloc]
    initWithName:[self binaryNameForBinaryPath:binaryPath]
    architectures:archs
    path:binaryPath];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  // Is immutable.
  return self;
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

#pragma mark Private

+ (NSString *)binaryNameForBinaryPath:(NSString *)binaryPath
{
  return binaryPath.lastPathComponent;
}

@end
