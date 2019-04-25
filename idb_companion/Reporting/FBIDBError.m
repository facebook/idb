// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBIDBError.h"

NSString *const FBIDBErrorDomain = @"com.facebook.idb";

@implementation FBIDBError

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  [self inDomain:FBIDBErrorDomain];

  return self;
}

@end
