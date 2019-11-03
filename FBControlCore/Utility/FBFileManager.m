/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBFileManager.h"

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
