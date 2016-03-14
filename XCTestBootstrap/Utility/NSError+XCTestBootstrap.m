// Copyright 2004-present Facebook. All Rights Reserved.

#import "NSError+XCTestBootstrap.h"

@implementation NSError (XCTestBootstrap)

+ (instancetype)XCTestBootstrapErrorWithDescription:(NSString *)description
{
  return
  [NSError errorWithDomain:@"com.facebook.FBDeviceControl"
                      code:XCTestBootstrapErrorCodeGeneral
                  userInfo:@{
                             NSLocalizedDescriptionKey : description,
                             }
   ];
}

@end
