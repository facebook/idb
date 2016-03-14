// Copyright 2004-present Facebook. All Rights Reserved.

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, XCTestBootstrapCode) {
  XCTestBootstrapErrorCodeGeneral,
};

@interface NSError (XCTestBootstrap)

+ (instancetype)XCTestBootstrapErrorWithDescription:(NSString *)description;

@end
