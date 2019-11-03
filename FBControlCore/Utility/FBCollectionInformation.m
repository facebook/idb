/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBCollectionInformation.h"

#import "FBJSONConversion.h"

@implementation FBCollectionInformation

+ (NSString *)oneLineDescriptionFromArray:(NSArray *)array
{
  return [self oneLineDescriptionFromArray:array atKeyPath:@"description"];
}

+ (NSString *)oneLineDescriptionFromArray:(NSArray *)array atKeyPath:(NSString *)keyPath
{
  return [NSString stringWithFormat:@"[%@]", [[array valueForKeyPath:keyPath] componentsJoinedByString:@", "]];
}

+ (NSString *)oneLineJSONDescription:(id<FBJSONSerializable>)object
{
  return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:object.jsonSerializableRepresentation options:0 error:nil] encoding:NSUTF8StringEncoding];
}

+ (NSString *)oneLineDescriptionFromDictionary:(NSDictionary *)dictionary
{
  NSMutableArray<NSString *> *pieces = [NSMutableArray array];
  for (NSString *key in dictionary.allKeys) {
    NSString *piece = [NSString stringWithFormat:@"%@ => %@", key, dictionary[key]];
    [pieces addObject:piece];
  }
  return [NSString stringWithFormat:@"{%@}", [pieces componentsJoinedByString:@", "]];
}

+ (BOOL)isArrayHeterogeneous:(NSArray *)array withClass:(Class)cls
{
  NSParameterAssert(cls);
  if (![array isKindOfClass:NSArray.class]) {
    return NO;
  }
  for (id object in array) {
    if (![object isKindOfClass:cls]) {
      return NO;
    }
  }
  return YES;
}

+ (BOOL)isDictionaryHeterogeneous:(NSDictionary *)dictionary keyClass:(Class)keyCls valueClass:(Class)valueCls
{
  NSParameterAssert(keyCls);
  NSParameterAssert(valueCls);
  if (![dictionary isKindOfClass:NSDictionary.class]) {
    return NO;
  }
  for (id object in dictionary.allKeys) {
    if (![object isKindOfClass:keyCls]) {
      return NO;
    }
  }
  for (id object in dictionary.allValues) {
    if (![object isKindOfClass:valueCls]) {
      return NO;
    }
  }
  return YES;
}

@end
