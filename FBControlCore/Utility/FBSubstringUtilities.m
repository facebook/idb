/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
