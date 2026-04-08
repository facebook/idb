/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>

#pragma mark - Expose Private Interface for Testing

@interface FBSimulatorDebuggerCommands (Testing)

@property (nonatomic, weak, readonly) FBSimulator *simulator;
@property (nonatomic, copy, readonly) NSString *debugServerPath;

+ (NSString *)debugServerPath;
- (instancetype)initWithSimulator:(FBSimulator *)simulator debugServerPath:(NSString *)debugServerPath;

@end

#pragma mark - Simulator Test Double

/**
 A minimal test double that captures the FBApplicationLaunchConfiguration
 passed to launchApplication:. This lets us verify the business logic of
 FBSimulatorDebuggerCommands without a real simulator.
 */
@interface FBSimulatorDebuggerTests_SimulatorDouble : NSObject

@property (nonatomic, strong) dispatch_queue_t workQueue;
@property (nonatomic, strong, nullable) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, nullable) FBApplicationLaunchConfiguration *capturedLaunchConfiguration;
@property (nonatomic, strong) FBMutableFuture *launchFuture;

@end

@implementation FBSimulatorDebuggerTests_SimulatorDouble

- (instancetype)init
{
  self = [super init];
  if (self) {
    _workQueue = dispatch_queue_create("com.test.debugger.workQueue", DISPATCH_QUEUE_SERIAL);
    _launchFuture = FBMutableFuture.future;
  }
  return self;
}

- (FBFuture *)launchApplication:(FBApplicationLaunchConfiguration *)configuration
{
  self.capturedLaunchConfiguration = configuration;
  return self.launchFuture;
}

@end

#pragma mark - Tests

@interface FBSimulatorDebuggerCommandsTests : XCTestCase
@end

@implementation FBSimulatorDebuggerCommandsTests

#pragma mark - Launch Configuration

- (void)testLaunchDebugServerConfiguresApplicationForDebugging
{
  // launchDebugServerForHostApplication:port: must create a launch configuration
  // that is specifically tailored for debugging: the app must wait for the
  // debugger to attach, must fail if already running (to avoid inconsistent
  // state), and must not inject any custom arguments or environment variables
  // that could interfere with the debug session.
  FBSimulatorDebuggerTests_SimulatorDouble *simulatorDouble = [[FBSimulatorDebuggerTests_SimulatorDouble alloc] init];
  FBSimulatorDebuggerCommands *commands = [[FBSimulatorDebuggerCommands alloc]
    initWithSimulator:(FBSimulator *)simulatorDouble
    debugServerPath:@"/fake/debugserver"];

  FBBundleDescriptor *app = [[FBBundleDescriptor alloc] initWithName:@"MyApp"
                                                          identifier:@"com.example.myapp"
                                                                path:@"/path/to/MyApp.app"
                                                              binary:nil];

  [commands launchDebugServerForHostApplication:app port:12345];

  FBApplicationLaunchConfiguration *config = simulatorDouble.capturedLaunchConfiguration;
  XCTAssertNotNil(config, @"Should have captured the launch configuration");
  XCTAssertTrue(config.waitForDebugger,
    @"Must launch with waitForDebugger=YES so the debugger can attach before execution begins");
  XCTAssertEqual(config.launchMode, FBApplicationLaunchModeFailIfRunning,
    @"Must use FailIfRunning to prevent attaching to an already-running app instance");
  XCTAssertEqualObjects(config.arguments, @[],
    @"No custom arguments should be passed to the debugged application");
  XCTAssertEqualObjects(config.environment, @{},
    @"No custom environment variables should be passed to the debugged application");
}

- (void)testLaunchDebugServerUsesApplicationDescriptorProperties
{
  // The launch configuration must correctly propagate the bundle identifier
  // and name from the provided FBBundleDescriptor. The bundle identifier is
  // used to locate and launch the correct app, while the name is used for
  // display purposes.
  FBSimulatorDebuggerTests_SimulatorDouble *simulatorDouble = [[FBSimulatorDebuggerTests_SimulatorDouble alloc] init];
  FBSimulatorDebuggerCommands *commands = [[FBSimulatorDebuggerCommands alloc]
    initWithSimulator:(FBSimulator *)simulatorDouble
    debugServerPath:@"/fake/debugserver"];

  FBBundleDescriptor *app = [[FBBundleDescriptor alloc] initWithName:@"SpecialApp"
                                                          identifier:@"com.example.special"
                                                                path:@"/path/to/SpecialApp.app"
                                                              binary:nil];

  [commands launchDebugServerForHostApplication:app port:9999];

  FBApplicationLaunchConfiguration *config = simulatorDouble.capturedLaunchConfiguration;
  XCTAssertEqualObjects(config.bundleID, @"com.example.special",
    @"Must use the bundle identifier from the application descriptor to launch the correct app");
  XCTAssertEqualObjects(config.bundleName, @"SpecialApp",
    @"Must use the bundle name from the application descriptor for display purposes");
}

#pragma mark - Path Construction

- (void)testDebugServerPathCombinesXcodeContentsDirectoryWithLLDBRelativePath
{
  // The debugServerPath must correctly locate the LLDB debugserver binary
  // within the Xcode installation. An incorrect path would cause the debug
  // server process to fail to launch, breaking the entire debug workflow.
  NSString *path = [FBSimulatorDebuggerCommands debugServerPath];
  NSString *contentsDirectory = FBXcodeConfiguration.contentsDirectory;
  NSString *expectedPath = [contentsDirectory stringByAppendingPathComponent:@"SharedFrameworks/LLDB.framework/Resources/debugserver"];
  XCTAssertEqualObjects(path, expectedPath,
    @"debugServerPath must combine Xcode Contents directory with LLDB debugserver relative path to locate the binary correctly");
}

@end
