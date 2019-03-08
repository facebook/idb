/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSubstringUtilities.h"

@implementation FBSubstringUtilities

+ (NSString *)substringAfterNeedle:(NSString *)needle inHaystack:(NSString *)haystack
{
  NSRange markerRange = [haystack rangeOfString:needle];
  if (markerRange.location == NSNotFound) {
    return haystack;
  }
  const NSUInteger consoleNewLogEntryPosition = (markerRange.location + needle.length);
  return [haystack substringWithRange:NSMakeRange(consoleNewLogEntryPosition, haystack.length - consoleNewLogEntryPosition)];
}

+ (NSString *)substringOf:(NSString *)string withLastCharacterCount:(NSUInteger)characterCount
{
  const NSUInteger markerLength = MIN(string.length, characterCount);
  return [string substringWithRange:NSMakeRange(string.length - markerLength, markerLength)];
}

@end
