// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBXCTestKitFixtures.h"

#import <FBSimulatorControl/FBSimulatorControl.h>

@implementation FBXCTestKitFixtures

+ (NSString *)createTemporaryDirectory
{
  NSError *error;
  NSFileManager *fileManager = [NSFileManager defaultManager];

  NSString *temporaryDirectory =
      [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  [fileManager createDirectoryAtPath:temporaryDirectory withIntermediateDirectories:YES attributes:nil error:&error];
  NSAssert(!error, @"Could not create temporary directory");

  return temporaryDirectory;
}

+ (NSString *)tableSearchApplicationPath
{
  return [[[NSBundle bundleForClass:self] pathForResource:@"TableSearch" ofType:@"app"]
      stringByAppendingPathComponent:@"TableSearch"];
}

+ (NSString *)simpleTestTargetPath
{
  return [[NSBundle bundleForClass:self] pathForResource:@"SimpleTestTarget" ofType:@"xctest"];
}

@end
