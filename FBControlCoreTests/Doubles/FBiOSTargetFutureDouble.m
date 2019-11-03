/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTargetFutureDouble.h"

@implementation FBiOSTargetFutureDouble

- (instancetype)initWithIdentifier:(NSString *)identifier succeed:(BOOL)succeed
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _identifier = identifier;
  _succeed = succeed;

  return self;
}

+ (FBiOSTargetFutureType)futureType
{
  return @"test-double";
}

static NSString *const KeyIdentifier = @"identifier";
static NSString *const KeySucceed = @"succeed";

+ (nullable instancetype)inflateFromJSON:(id)json error:(NSError **)error
{
  NSString *identifier = json[KeyIdentifier];
  if (![identifier isKindOfClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a String for %@", identifier, KeyIdentifier]
      fail:error];
  }
  NSNumber *succeed = json[KeySucceed];
  if (![succeed isKindOfClass:NSNumber.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a Number for %@", succeed, KeySucceed]
      fail:error];
  }
  return [[FBiOSTargetFutureDouble alloc] initWithIdentifier:identifier succeed:succeed.boolValue];
}

- (id)jsonSerializableRepresentation
{
  return @{
    KeyIdentifier: self.identifier,
    KeySucceed: @(self.succeed),
  };
}

- (FBFuture<id<FBiOSTargetContinuation>> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBDataConsumer>)consumer reporter:(id<FBEventReporter>)reporter
{
  if (self.succeed) {
    return [FBFuture futureWithResult:FBiOSTargetContinuationDone(self.class.futureType)];
  } else {
    NSError *error = [NSError errorWithDomain:@"" code:0 userInfo:nil];
    return [FBFuture futureWithError:error];
  }
}

- (BOOL)isEqual:(FBiOSTargetFutureDouble *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return [self.identifier isEqualToString:object.identifier] && self.succeed == object.succeed;
}

- (NSUInteger)hash
{
  return self.identifier.hash;
}

@end
