/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBiOSTargetActionDouble.h"

@implementation FBiOSTargetActionDouble

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

+ (FBiOSTargetActionType)actionType
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
  return [[FBiOSTargetActionDouble alloc] initWithIdentifier:identifier succeed:succeed.boolValue];
}

- (id)jsonSerializableRepresentation
{
  return @{
    KeyIdentifier: self.identifier,
    KeySucceed: @(self.succeed),
  };
}

- (BOOL)runWithTarget:(id<FBiOSTarget>)target delegate:(id<FBiOSTargetActionDelegate>)delegate error:(NSError **)error
{
  return self.succeed;
}

- (BOOL)isEqual:(FBiOSTargetActionDouble *)object
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
