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
  int bracketCounter = 0;
  BOOL characterEscaped = false;
  BOOL inString = false;

  NSMutableDictionary<NSString *, id> *concatenatedJson = [NSMutableDictionary new];
  NSMutableString *json = [NSMutableString new];
  
  NSUInteger len = [str length];
  unichar buffer[len+1];

  [str getCharacters:buffer range:NSMakeRange(0, len)];

  for(NSUInteger i = 0; i < len; i++) {
    unichar c = buffer[i];
    
    BOOL escaped = characterEscaped;
    characterEscaped = false;
    if (escaped) {
      [json appendFormat:@"%C", c];
      continue;
    }
    if (!inString) {
      if (c == '\n') {
        continue;
      }
      if (c == '{') {
        bracketCounter += 1;
      } else if (c == '}') {
        bracketCounter -= 1;
      }
    }
    if (c == '\\') {
      characterEscaped = true;
    }
    if (c == '"') {
      inString = !inString;
    }
    [json appendFormat:@"%C", c];
    if (bracketCounter == 0) {
      NSDictionary<NSString *, id> *parsed = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:error];
      if (!parsed) {
        return nil;
      }
      json = [NSMutableString new];
      [concatenatedJson addEntriesFromDictionary:parsed];
    }
  }

  return concatenatedJson;
}

@end
