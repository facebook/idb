/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBProcessOutputConfiguration.h"

NSString *const FBProcessOutputToFileDefaultLocation = @"FBProcessOutputToFileDefaultLocation";

@implementation FBProcessOutputConfiguration

#pragma mark Initializers

+ (nullable instancetype)configurationWithStdOut:(id)stdOut stdErr:(id)stdErr error:(NSError **)error
{
  if (![stdOut isKindOfClass:NSNull.class] && ![stdOut isKindOfClass:NSString.class] && ![stdOut conformsToProtocol:@protocol(FBDataConsumer)]) {
    return [[FBControlCoreError
      describeFormat:@"'stdout' should be (Null | String | FBDataConsumer) but is %@",  stdOut]
      fail:error];
  }

  if (![stdErr isKindOfClass:NSNull.class] && ![stdErr isKindOfClass:NSString.class] && ![stdErr conformsToProtocol:@protocol(FBDataConsumer)]) {
    return [[FBControlCoreError
      describeFormat:@"'stderr' should be (Null | String | FBDataConsumer) but is %@",  stdErr]
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

#pragma mark Public Methods

- (FBFuture<FBProcessIO *> *)createIOForTarget:(id<FBiOSTarget>)target
{
  return [[FBFuture
    futureWithFutures:@[
      [self createOutputForTarget:target selector:@selector(stdOut)],
      [self createOutputForTarget:target selector:@selector(stdErr)],
    ]]
    onQueue:target.asyncQueue map:^(NSArray<FBProcessOutput *> *outputs) {
      return [[FBProcessIO alloc] initWithStdIn:nil stdOut:outputs[0] stdErr:outputs[1]];
    }];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
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

#pragma mark Private

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

- (FBFuture<FBProcessOutput *> *)createOutputForTarget:(id<FBiOSTarget>)target selector:(SEL)selector
{
  id output = [self performSelector:selector];
  if ([output isKindOfClass:NSString.class]) {
    NSString *path = output;
      if (![NSFileManager.defaultManager createFileAtPath:path contents:NSData.data attributes:nil]) {
        return [[FBControlCoreError
          describeFormat:@"Could not create '%@' at path '%@' for config '%@'", NSStringFromSelector(selector), path, self]
          failFuture];
      }
      return [FBFuture futureWithResult:[FBProcessOutput outputForFilePath:path]];
  }
  id<FBDataConsumer> consumer = [self performSelector:selector];
  if ([consumer conformsToProtocol:@protocol(FBDataConsumer)]) {
    return [FBFuture futureWithResult:[FBProcessOutput outputForDataConsumer:consumer]];

  }
  return [FBFuture futureWithResult:FBProcessOutput.outputForNullDevice];
}

#pragma clang diagnostic pop

@end
