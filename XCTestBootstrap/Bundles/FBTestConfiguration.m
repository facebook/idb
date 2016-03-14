// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBTestConfiguration.h"

#import <XCTest/XCTestConfiguration.h>

#import "FBFileManager.h"
#import "NSFileManager+FBFileManager.h"

@interface FBTestConfiguration ()
@property (nonatomic, copy) NSUUID *sessionIdentifier;
@property (nonatomic, copy) NSString *moduleName;
@property (nonatomic, copy) NSString *testBundlePath;
@property (nonatomic, copy) NSString *path;
@end

@implementation FBTestConfiguration
@end


@interface FBTestConfigurationBuilder ()
@property (nonatomic, strong) id<FBFileManager> fileManager;
@property (nonatomic, copy) NSUUID *sessionIdentifier;
@property (nonatomic, copy) NSString *moduleName;
@property (nonatomic, copy) NSString *testBundlePath;
@property (nonatomic, copy) NSString *savePath;
@end

@implementation FBTestConfigurationBuilder

+ (instancetype)builder
{
  return [self.class builderWithFileManager:[NSFileManager defaultManager]];
}

+ (instancetype)builderWithFileManager:(id<FBFileManager>)fileManager
{
  FBTestConfigurationBuilder *builder = [self.class new];
  builder.fileManager = fileManager;
  return builder;
}

- (instancetype)withSessionIdentifier:(NSUUID *)sessionIdentifier
{
  self.sessionIdentifier = sessionIdentifier;
  return self;
}

- (instancetype)withModuleName:(NSString *)moduleName
{
  self.moduleName = moduleName;
  return self;
}

- (instancetype)withTestBundlePath:(NSString *)testBundlePath
{
  self.testBundlePath = testBundlePath;
  return self;
}

- (instancetype)saveAs:(NSString *)savePath
{
  self.savePath = savePath;
  return self;
}

- (FBTestConfiguration *)build
{
  if (self.savePath) {
    NSAssert(self.fileManager, @"fileManager is required to save test configuration");
    NSError *error;
    XCTestConfiguration *testConfiguration = [XCTestConfiguration new];
    testConfiguration.sessionIdentifier = self.sessionIdentifier;
    testConfiguration.testBundleURL = (self.testBundlePath ? [NSURL fileURLWithPath:self.testBundlePath] : nil);
    testConfiguration.treatMissingBaselinesAsFailures = NO;
    testConfiguration.productModuleName = self.moduleName;
    testConfiguration.reportResultsToIDE = YES;
    testConfiguration.pathToXcodeReportingSocket = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:testConfiguration];
    if (![self.fileManager writeData:data toFile:self.savePath options:NSDataWritingAtomic error:&error]) {
      return nil;
    }
  }

  FBTestConfiguration *configuration = [FBTestConfiguration new];
  configuration.sessionIdentifier = self.sessionIdentifier;
  configuration.testBundlePath = self.testBundlePath;
  configuration.moduleName = self.moduleName;
  configuration.path = self.savePath;
  return configuration;
}

@end
