/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <stdio.h>

#import "FBConcatedJsonParser.h"

@implementation FBConcatedJsonParser

#pragma mark Public

+ (nullable NSDictionary<NSString *, id> *)parseConcatenatedJSONFromString:(NSString *)str error:(NSError **)error{
  __block int bracketCounter = 0;
  __block BOOL characterEscaped = false;
  __block BOOL inString = false;
  __block NSError *err = nil;

  NSMutableDictionary<NSString *, id> *concatenatedJson = [NSMutableDictionary new];
  __block NSMutableString *json = [NSMutableString new];
  
  [str enumerateSubstringsInRange:NSMakeRange(0, [str length]) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString * _Nullable substring, NSRange substringRange, NSRange enclosingRange, BOOL * _Nonnull stop) {
    if (!substring) {
      return;
    }
    NSString *c = substring;
    BOOL escaped = characterEscaped;
    characterEscaped = false;
    if (escaped) {
      [json appendString:c];
      return;
    }
    if (!inString) {
      if ([c isEqualToString: @"\n"]) {
        return;
      }
      if ([c isEqualToString: @"{"]) {
        bracketCounter += 1;
      } else if ([c isEqualToString:@"}"]) {
        bracketCounter -= 1;
      }
    }
    if ([c isEqualToString: @"\\"]) {
      characterEscaped = true;
    }
    if ([c isEqualToString: @"\""]) {
      inString = !inString;
    }
    [json appendString:c];
    if (bracketCounter == 0) {
      NSDictionary<NSString *, id> *parsed = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&err];
      if (!parsed) {
        *stop = YES;
      }
      json = [NSMutableString new];
      [concatenatedJson addEntriesFromDictionary:parsed];
    }
  }];
  if (err) {
    *error = err;
    return nil;
  }

  return concatenatedJson;
}

@end
