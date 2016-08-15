// Copyright 2004-present Facebook. All Rights Reserved.

#import <Foundation/Foundation.h>

#import <FBXCTestKit/FBXCTestKit.h>

int main(int argc, const char *argv[])
{
  @autoreleasepool {
    if (![FBXCTestBootstrapper bootstrap]) {
      return 2;
    }
  }
  return 0;
}
