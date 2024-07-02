/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestConfiguration.h"

#import <FBControlCore/FBControlCore.h>

#import <XCTestPrivate/XCTCapabilitiesBuilder.h>
#import <XCTestPrivate/XCTestConfiguration.h>
#import <XCTestPrivate/XCTTestIdentifier.h>
#import <XCTestPrivate/XCTTestIdentifierSet.h>
#import <XCTestPrivate/XCTTestIdentifierSetBuilder.h>

#import <objc/runtime.h>

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

@implementation FBTestConfiguration

+ (nullable instancetype)configurationByWritingToFileWithSessionIdentifier:(NSUUID *)sessionIdentifier moduleName:(NSString *)moduleName testBundlePath:(NSString *)testBundlePath uiTesting:(BOOL)uiTesting testsToRun:(nullable NSSet<NSString *> *)testsToRun testsToSkip:(nullable NSSet<NSString *> *)testsToSkip targetApplicationPath:(nullable NSString *)targetApplicationPath targetApplicationBundleID:(nullable NSString *)targetApplicationBundleID testApplicationDependencies:(nullable NSDictionary<NSString *, NSString*> *)testApplicationDependencies automationFrameworkPath:(nullable NSString *)automationFrameworkPath reportActivities:(BOOL)reportActivities error:(NSError **)error
{
  // Construct the XCTestConfiguration class.
  XCTestConfiguration *testConfiguration = [objc_lookUpClass("XCTestConfiguration") new];
  testConfiguration.sessionIdentifier = sessionIdentifier;
  testConfiguration.testBundleURL = (testBundlePath ? [NSURL fileURLWithPath:testBundlePath] : nil);
  testConfiguration.treatMissingBaselinesAsFailures = NO;
  testConfiguration.productModuleName = moduleName;
  testConfiguration.reportResultsToIDE = YES;
  testConfiguration.testsMustRunOnMainThread = uiTesting;
  testConfiguration.initializeForUITesting = uiTesting;
  [self setTestsToRun: testsToRun andTestsToSkip: testsToSkip to: testConfiguration];
  testConfiguration.targetApplicationPath = targetApplicationPath;
  testConfiguration.targetApplicationBundleID = targetApplicationBundleID;
  testConfiguration.automationFrameworkPath = automationFrameworkPath;
  testConfiguration.reportActivities = reportActivities;
  testConfiguration.testsDrivenByIDE = NO;
  testConfiguration.testApplicationDependencies = testApplicationDependencies;

  XCTCapabilitiesBuilder *capabilitiesBuilder = [objc_lookUpClass("XCTCapabilitiesBuilder") new];
  [capabilitiesBuilder registerCapability:@"XCTIssue capability"];
  [capabilitiesBuilder registerCapability:@"ubiquitous test identifiers"];
  testConfiguration.IDECapabilities = [capabilitiesBuilder capabilities];

  NSData *data = [NSKeyedArchiver archivedDataWithRootObject:testConfiguration requiringSecureCoding:NO error:nil];

  // Write it to file.
  NSString *testBundleContainerPath = testBundlePath.stringByDeletingLastPathComponent;
  NSString *testConfigPath = [testBundleContainerPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.xctestconfiguration", moduleName, sessionIdentifier.UUIDString]];
  if (![data writeToFile:testConfigPath options:NSDataWritingAtomic error:error]) {
    return nil;
  }
  return [self configurationWithSessionIdentifier:sessionIdentifier moduleName:moduleName testBundlePath:testBundlePath path:testConfigPath uiTesting:uiTesting xcTestConfiguration:testConfiguration];
}

+ (void) setTestsToRun: (NSSet<NSString *> *) toRun andTestsToSkip: (NSSet<NSString *> *) toSkip to: (XCTestConfiguration *) configuration
{
  if (FBXcodeConfiguration.isXcode12_5OrGreater) {
    configuration.testsToSkip = [self xctestIdentifierSetFromSetOfStrings:toSkip];
    configuration.testsToRun = [self xctestIdentifierSetFromSetOfStrings:toRun];
  } else {
    configuration.testsToSkip = toSkip;
    configuration.testsToRun = toRun;
  }
}

+ (nullable XCTTestIdentifierSet *)xctestIdentifierSetFromSetOfStrings:(nullable NSSet<NSString *> *) tests
{
  if (tests == nil) {
    return nil;
  }

  Class XCTTestIdentifierSetBuilder_class = objc_lookUpClass("XCTTestIdentifierSetBuilder");
  XCTTestIdentifierSetBuilder *b = [[XCTTestIdentifierSetBuilder_class alloc] init];
  Class XCTTestIdentifier_class = objc_lookUpClass("XCTTestIdentifier");;
  for (NSString *test in tests) {
    XCTTestIdentifier *identifier = [[XCTTestIdentifier_class alloc] initWithStringRepresentation: test preserveModulePrefix:YES];
    [b addTestIdentifier: identifier];
  }

  return b.testIdentifierSet;
}

+ (instancetype)configurationWithSessionIdentifier:(NSUUID *)sessionIdentifier moduleName:(NSString *)moduleName testBundlePath:(NSString *)testBundlePath path:(NSString *)path uiTesting:(BOOL)uiTesting xcTestConfiguration:(XCTestConfiguration *)xcTestConfiguration
{
  return [[self alloc]
    initWithSessionIdentifier:sessionIdentifier
    moduleName:moduleName
    testBundlePath:testBundlePath
    path:path
    uiTesting:uiTesting
    xcTestConfiguration:xcTestConfiguration];
}

- (instancetype)initWithSessionIdentifier:(NSUUID *)sessionIdentifier moduleName:(NSString *)moduleName testBundlePath:(NSString *)testBundlePath path:(NSString *)path uiTesting:(BOOL)uiTesting xcTestConfiguration:(XCTestConfiguration *)xcTestConfiguration
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _sessionIdentifier = sessionIdentifier;
  _moduleName = moduleName;
  _testBundlePath = testBundlePath;
  _path = path;
  _shouldInitializeForUITesting = uiTesting;
  _xcTestConfiguration=xcTestConfiguration;

  return self;
}

@end

#pragma GCC diagnostic pop
