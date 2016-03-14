/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "NSFileManager+FBFileManager.h"

@implementation NSFileManager (FBFileManager)

- (BOOL)writeData:(NSData *)data toFile:(NSString *)toFile options:(NSDataWritingOptions)options error:(NSError **)error
{
  return [data writeToFile:toFile options:options error:error];
}

- (NSDictionary *)dictionaryWithPath:(NSString *)path
{
  return [NSDictionary dictionaryWithContentsOfFile:path];
}

@end
