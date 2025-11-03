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
@property (nonatomic, strong, nullable, readwrite) FBMacDevice *device;
@end

@implementation FBMacDeviceTests

- (void)setUp
{
  [super setUp];
  self.device = [[FBMacDevice alloc] init];
}

- (BOOL)tearDownWithError:(NSError *__autoreleasing  _Nullable *)error
{
  
  NSError *err = nil;
  [[self.device restorePrimaryDeviceState] awaitWithTimeout:5 error:&err];
  if (err) {
    NSLog(@"Failed to tearDown test gracefully %@. Further tests may be affected", err.description);
  }
  *error = err;
  return err == nil;
}

- (void)testMacComparsion
{
  FBMacDevice *anotherDevice = [[FBMacDevice alloc] init];
  NSComparisonResult comparsionResult = [self.device compare:anotherDevice];
  
  XCTAssertEqual(comparsionResult, NSOrderedSame,
                 @"We should have only one exemplar of FBMacDevice, so this is same");
}

- (void)testMacStateRestorationWithEmptyTasks
{
  XCTAssertNotNil([[self.device restorePrimaryDeviceState] result],
                  @"State restoration without launched task should complete immidiately");
}

-(void)testInstallNotExistedApplicationAtPath
{
  __auto_type installTask = [self.device installApplicationWithPath:@"/not/existed/path"];
  XCTAssertNotNil(installTask.error,
                  @"Installing not existed app should fail immidiately");
}

-(void)testInstallExistedApplicationAtPath
{
  NSError *err = nil;
  __auto_type res = [self installDummyApplicationWithError:&err];
  XCTAssertNil(err, @"Failed to install application");
  
  XCTAssertTrue([res.bundle.identifier isEqualToString: @"com.facebook.MacCommonApp"],
                @"Dummy application should install properly");
}

-(void)testUninstallApplicationByIncorrectBundleID
{
  XCTAssertNotNil([self.device uninstallApplicationWithBundleID:@"not.existed"].error);
}

-(void)testUninstallApplicationByIncorrectAppPath
{
  NSError *err = nil;
  __auto_type app = [self installDummyApplicationWithError:&err];
  XCTAssertNil(err,
               @"Precondition failure");
  
  __auto_type rightPath = app.bundle.path;
  
  // Substitute path of bundle to simulate corruption of path to app
  [app.bundle setValue:@"incorrect/path" forKey:@"_path"];

  XCTAssertNil([self.device uninstallApplicationWithBundleID:app.bundle.identifier].error,
                  @"Error should not be thrown when bundle path is incorrect");

  // Restore correct path to make tearDown behave properly
  [app.bundle setValue:rightPath forKey:@"_path"];
}

-(void)testLaunchingNotInstalledAppByBuntleID
{
  FBApplicationLaunchConfiguration *config = [[FBApplicationLaunchConfiguration alloc] initWithBundleID:@"not.existed"
                                                                                             bundleName:@"not.existed"
                                                                                              arguments:@[]
                                                                                            environment:@{}
                                                                                        waitForDebugger:NO
                                                                                                     io:FBProcessIO.outputToDevNull
                                                                                             launchMode:FBApplicationLaunchModeRelaunchIfRunning];
  __auto_type launchAppFuture = [self.device launchApplication:config];
  
  XCTAssertNotNil([launchAppFuture error],
                  @"Launhing not existed app should fail immidiately");
}

-(void)testLaunchingExistedApp
{
  NSError *err = nil;
  __auto_type installResult = [self installDummyApplicationWithError:&err];
  XCTAssertNil(err,
               @"Precondition failure");
  
  FBApplicationLaunchConfiguration *config = [[FBApplicationLaunchConfiguration alloc] initWithBundleID:installResult.bundle.identifier
                                                                                             bundleName:installResult.bundle.name
                                                                                              arguments:@[]
                                                                                            environment:@{}
                                                                                        waitForDebugger:NO
                                                                                                     io:FBProcessIO.outputToDevNull
                                                                                             launchMode:FBApplicationLaunchModeRelaunchIfRunning];
  
  [[self.device launchApplication:config] awaitWithTimeout:5 error:&err];
  
  XCTAssertNil(err,
               @"Failed to launch installed application");
}

-(FBInstalledApplication *)installDummyApplicationWithError:(NSError **)error
{
  NSError *err = nil;
  __auto_type descriptor = [FBMacDeviceTests macCommonApplicationWithError:&err];
  if (err) {
    *error = err;
    return nil;
  }
  __auto_type installTask = [self.device installApplicationWithPath: descriptor.path];
  return [installTask awaitWithTimeout:5 error:error];
}


@end
