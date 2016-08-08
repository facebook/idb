// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBXCTestError.h"

NSString *const FBTestErrorDomain = @"com.facebook.FBTestError";

@implementation FBXCTestError

- (instancetype)init
{
  self = [super init];
  if (self) {
    [self inDomain:FBTestErrorDomain];
  }
  return self;
}

@end
