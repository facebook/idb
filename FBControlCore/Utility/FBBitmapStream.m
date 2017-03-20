/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBBitmapStream.h"

#import "FBCollectionInformation.h"

FBTerminationHandleType const FBTerminationHandleTypeVideoStreaming = @"VideoStreaming";

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
