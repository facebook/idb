/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBXCTestBootstrapFixtures.h"

@interface FBMacDeviceTests : XCTestCase
@property (nullable, nonatomic, readwrite, strong) FBMacDevice *device;
@property (nullable, nonatomic, readwrite, strong) FBInstalledApplication *installedApp;
@property (nullable, nonatomic, readwrite, copy) NSString *tempInstallDir;
@end

@implementation FBMacDeviceTests

- (void)setUp
{
  [super setUp];
  self.device = [[FBMacDevice alloc] init];

  NSError *err = nil;
  __auto_type descriptor = [FBMacDeviceTests macCommonApplicationWithError:&err];
  NSAssert(descriptor != nil, @"Failed to load MacCommonApp fixture: %@", err);

  // Copy the .app to a temporary directory so that uninstall (which deletes the
  // installed path) does not destroy the fixture inside the test bundle.
  self.tempInstallDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
  NSString *tempDir = self.tempInstallDir;
  NSAssert(
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:&err],
    @"Failed to create temp dir: %@",
    err
  );
  NSString *destPath = [tempDir stringByAppendingPathComponent:[descriptor.path lastPathComponent]];
  NSAssert(
    [[NSFileManager defaultManager] copyItemAtPath:descriptor.path toPath:destPath error:&err],
    @"Failed to copy fixture app: %@",
    err
  );

  self.installedApp = [[self.device installApplicationWithPath:destPath] awaitWithTimeout:5 error:&err];
  NSAssert(self.installedApp != nil, @"Failed to install dummy app: %@", err);
}

- (BOOL)tearDownWithError:(NSError *__autoreleasing _Nullable *)error
{
  NSError *err = nil;
  [[self.device restorePrimaryDeviceState] awaitWithTimeout:5 error:&err];
  if (err) {
    NSLog(@"Failed to tearDown test gracefully %@. Further tests may be affected", err.description);
  }
  if (self.tempInstallDir) {
    [[NSFileManager defaultManager] removeItemAtPath:self.tempInstallDir error:nil];
    self.tempInstallDir = nil;
  }
  *error = err;
  return err == nil;
}

- (void)testMacComparsion
{
  FBMacDevice *anotherDevice = [[FBMacDevice alloc] init];
  NSComparisonResult comparsionResult = [self.device compare:anotherDevice];

  XCTAssertEqual(
    comparsionResult,
    NSOrderedSame,
    @"We should have only one exemplar of FBMacDevice, so this is same"
  );
}

- (void)testMacStateRestorationWithEmptyTasks
{
  XCTAssertNotNil(
    [[self.device restorePrimaryDeviceState] result],
    @"State restoration without launched task should complete immidiately"
  );
}

- (void)testInstallNotExistedApplicationAtPath
{
  __auto_type installTask = [self.device installApplicationWithPath:@"/not/existed/path"];
  XCTAssertNotNil(
    installTask.error,
    @"Installing not existed app should fail immidiately"
  );
}

- (void)testInstallExistedApplicationAtPath
{
  XCTAssertTrue(
    [self.installedApp.bundle.identifier isEqualToString:@"com.facebook.MacCommonApp"],
    @"Dummy application should install properly"
  );
}

- (void)testUninstallApplicationByIncorrectBundleID
{
  XCTAssertNotNil([self.device uninstallApplicationWithBundleID:@"not.existed"].error);
}

- (void)testLaunchingNotInstalledAppByBuntleID
{
  FBApplicationLaunchConfiguration *config = [[FBApplicationLaunchConfiguration alloc] initWithBundleID:@"not.existed"
                                                                                             bundleName:@"not.existed"
                                                                                              arguments:@[]
                                                                                            environment:@{}
                                                                                        waitForDebugger:NO
                                                                                                     io:FBProcessIO.outputToDevNull
                                                                                             launchMode:FBApplicationLaunchModeRelaunchIfRunning];
  __auto_type launchAppFuture = [self.device launchApplication:config];

  XCTAssertNotNil(
    [launchAppFuture error],
    @"Launhing not existed app should fail immidiately"
  );
}

- (void)testLaunchingExistedApp
{
  NSError *err = nil;
  FBApplicationLaunchConfiguration *config = [[FBApplicationLaunchConfiguration alloc] initWithBundleID:self.installedApp.bundle.identifier
                                                                                             bundleName:self.installedApp.bundle.name
                                                                                              arguments:@[]
                                                                                            environment:@{}
                                                                                        waitForDebugger:NO
                                                                                                     io:FBProcessIO.outputToDevNull
                                                                                             launchMode:FBApplicationLaunchModeRelaunchIfRunning];

  [[self.device launchApplication:config] awaitWithTimeout:5 error:&err];

  XCTAssertNil(
    err,
    @"Failed to launch installed application"
  );
}

@end
