/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBCollectionDescriptions.h"

@implementation FBCollectionDescriptions

+ (NSString *)oneLineDescriptionFromArray:(NSArray *)array
{
  return [self oneLineDescriptionFromArray:array atKeyPath:@"description"];
}

+ (NSString *)oneLineDescriptionFromArray:(NSArray *)array atKeyPath:(NSString *)keyPath
{
  return [NSString stringWithFormat:@"[%@]", [[array valueForKeyPath:keyPath] componentsJoinedByString:@", "]];
}

+ (NSString *)oneLineDescriptionFromDictionary:(NSDictionary *)dictionary
{
  NSMutableString *string = [NSMutableString stringWithString:@"{"];
  for (NSString *key in dictionary.allKeys) {
    [string stringByAppendingFormat:@"%@ => %@, ", key, dictionary[key]];
  }
  [string appendString:@"}"];
  return string;
}

@end
