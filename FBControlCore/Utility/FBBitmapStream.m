/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBBitmapStream.h"

#import "FBCollectionInformation.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeVideoStreaming = @"VideoStreaming";

@implementation FBBitmapStreamAttributes

- (instancetype)initWithAttributes:(NSDictionary<NSString *, id> *)attributes
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _attributes = attributes;
  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [FBCollectionInformation oneLineDescriptionFromDictionary:self.attributes];
}

#pragma mark FBJSONSerializable

- (id)jsonSerializableRepresentation
{
  return self.attributes;
}

@end
