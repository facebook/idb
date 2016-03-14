// Copyright 2004-present Facebook. All Rights Reserved.

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
