/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessOutputConfiguration.h"

#import <FBControlCore/FBControlCore.h>

NSString *const FBProcessOutputToFileDefaultLocation = @"FBProcessOutputToFileDefaultLocation";

@implementation FBProcessOutputConfiguration

+ (nullable instancetype)configurationWithStdOut:(id)stdOut stdErr:(id)stdErr error:(NSError **)error
{
  if (![stdOut isKindOfClass:NSNull.class] && ![stdOut isKindOfClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"'stdout' should be Null | String but is %@",  stdOut]
      fail:error];
  }

  if (![stdErr isKindOfClass:NSNull.class] && ![stdErr isKindOfClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"'stderr' should be Null | String but is %@",  stdErr]
      fail:error];
  }
  return [[self alloc] initWithStdOut:stdOut stdErr:stdErr];
}

+ (instancetype)defaultOutputToFile
{
  return [[self alloc] initWithStdOut:FBProcessOutputToFileDefaultLocation stdErr:FBProcessOutputToFileDefaultLocation];
}

+ (instancetype)outputToDevNull
{
  return [[self alloc] init];
}

- (instancetype)init
{
  return [self initWithStdOut:NSNull.null stdErr:NSNull.null];
}

- (instancetype)initWithStdOut:(id)stdOut stdErr:(id)stdErr
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _stdOut = stdOut;
  _stdErr = stdErr;
  return self;
}

- (nullable instancetype)withStdOut:(id)stdOut error:(NSError **)error
{
  return [FBProcessOutputConfiguration configurationWithStdOut:stdOut stdErr:self.stdErr error:error];
}

- (nullable instancetype)withStdErr:(id)stdErr error:(NSError **)error
{
  return [FBProcessOutputConfiguration configurationWithStdOut:self.stdOut stdErr:stdErr error:error];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _stdOut = [coder decodeObjectForKey:NSStringFromSelector(@selector(stdOut))];
  _stdErr = [coder decodeObjectForKey:NSStringFromSelector(@selector(stdErr))];

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
  [coder encodeObject:self.stdOut forKey:NSStringFromSelector(@selector(stdOut))];
  [coder encodeObject:self.stdErr forKey:NSStringFromSelector(@selector(stdErr))];
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return [self.stdOut hash] ^ [self.stdErr hash];
}

- (BOOL)isEqual:(FBProcessOutputConfiguration *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return [self.stdOut isEqual:object.stdOut] && [self.stdErr isEqual:object.stdErr];
}

#pragma mark FBDebugDescribeable

- (NSString *)shortDescription
{
  return self.description;
}

- (NSString *)debugDescription
{
  return self.description;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"StdOut %@ | StdErr %@", self.stdOut, self.stdErr];
}

#pragma mark FBJSONSerializable

static NSString *StdOutKey = @"stdout";
static NSString *StdErrKey = @"stderr";

+ (instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBControlCoreError
      describeFormat:@"Process Output Configuration is not an Dictionary<String, Null|String> for %@", json]
      fail:error];
  }
  return [self configurationWithStdOut:json[StdOutKey] stdErr:json[StdErrKey] error:error];
}

- (NSDictionary *)jsonSerializableRepresentation
{
  return @{
    @"stdout": self.stdOut,
    @"stderr": self.stdErr,
  };
}

@end
