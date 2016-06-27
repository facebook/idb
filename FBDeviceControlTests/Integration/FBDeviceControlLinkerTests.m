// Copyright 2004-present Facebook. All Rights Reserved.

#import <XCTest/XCTest.h>

#import <FBDeviceControl/FBDeviceControl.h>
#import "FBDeviceTestPreparationStrategy.h"
#import "FBXCTestRunStrategy.h"
#import "FBCodeSignCommand.h"
#import "FBTestManager.h"

@interface FBDeviceControlLinkerTests : XCTestCase

@end

@implementation FBDeviceControlLinkerTests

- (void)testLinksPrivateFrameworks
{
  [FBDeviceControlFrameworkLoader initializeFrameworks];
}

- (void)testTheTest {
    FBCodeSignCommand *codesigner = [FBCodeSignCommand codeSignCommandWithIdentityName:@"iPhone Developer: Chris Fuentes (G7R46E5NX7)"];
    
    FBDeviceTestPreparationStrategy *testPrepareStrategy =
    [FBDeviceTestPreparationStrategy strategyWithTestRunnerApplicationPath:@"/Users/chrisf/calabash-xcuitest-server/Products/ipa/DeviceAgent/CBX-Runner.app"
                                                       applicationDataPath:@"/Users/chrisf/scratch/appData.xcappdata"
                                                            testBundlePath:@"/Users/chrisf/calabash-xcuitest-server/Products/ipa/DeviceAgent/CBX-Runner.app/PlugIns/CBX.xctest"
                                                    pathToXcodePlatformDir:@"/Applications/Xcode.app/Contents/Developer"
                                                          workingDirectory:@"/Users/chrisf"];
    
    NSError *err;
    FBiOSDeviceOperator *op = [FBiOSDeviceOperator operatorWithDeviceUDID:@"49a29c9e61998623e7909e35e8bae50dd07ef85f"
                                                         codesignProvider:codesigner
                                                                    error:&err];
    
    if (err) {
        NSLog(@"Error creating device operator: %@", err);
        return;
    }
    FBXCTestRunStrategy *testRunStrategy = [FBXCTestRunStrategy strategyWithDeviceOperator:op
                                                                       testPrepareStrategy:testPrepareStrategy
                                                                                  reporter:nil
                                                                                    logger:nil];
    NSError *innerError = nil;
    [testRunStrategy startTestManagerWithAttributes:@[] environment:@{} error:&innerError];
    
    if (!innerError) {
        [[NSRunLoop mainRunLoop] run];
    } else {
        NSLog(@"Err: %@", innerError);
    }
}

@end
