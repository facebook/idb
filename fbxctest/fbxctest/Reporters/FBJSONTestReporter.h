// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBXCTestReporter.h"

@interface FBJSONTestReporter : NSObject <FBXCTestReporter>

- (instancetype)initWithTestBundlePath:(NSString *)testBundlePath testType:(NSString *)testType;

@end
