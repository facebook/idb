/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBIDBCommandExecutor.h"

#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBDeviceControl/FBDeviceControl.h>

#import "FBXCTestDescriptor.h"
#import "FBXCTestRunRequest.h"
#import "FBXCTestRunRequest.h"
#import "FBIDBStorageManager.h"
#import "FBIDBError.h"
#import "FBIDBLogger.h"
#import "FBDsymInstallLinkToBundle.h"

FBFileContainerKind const FBFileContainerKindXctest = @"xctest";
FBFileContainerKind const FBFileContainerKindDylib = @"dylib";
FBFileContainerKind const FBFileContainerKindDsym = @"dsym";
FBFileContainerKind const FBFileContainerKindFramework = @"framework";

@interface FBIDBCommandExecutor ()

@property (nonatomic, strong, readonly) id<FBiOSTarget> target;
@property (nonatomic, strong, readonly) FBIDBLogger *logger;
@property (nonatomic, readonly) in_port_t debugserverPort;

@end

@implementation FBIDBCommandExecutor

#pragma mark Initializers

+ (instancetype)commandExecutorForTarget:(id<FBiOSTarget>)target storageManager:(FBIDBStorageManager *)storageManager temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory debugserverPort:(in_port_t)debugserverPort logger:(FBIDBLogger *)logger
{
  return [[self alloc] initWithTarget:target storageManager:storageManager temporaryDirectory:temporaryDirectory debugserverPort:debugserverPort logger:[logger withName:@"grpc_handler"]];
}

- (instancetype)initWithTarget:(id<FBiOSTarget>)target storageManager:(FBIDBStorageManager *)storageManager temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory debugserverPort:(in_port_t)debugserverPort logger:(FBIDBLogger *)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _target = target;
  _storageManager = storageManager;
  _temporaryDirectory = temporaryDirectory;
  _debugserverPort = debugserverPort;
  _logger = logger;

  return self;
}

#pragma mark Installation

- (FBFuture<NSDictionary<FBInstalledApplication *, id> *> *)list_apps:(BOOL)fetchProcessState
{
  return [[FBFuture
    futureWithFutures:@[
      [self.target installedApplications],
      fetchProcessState ? [self.target runningApplications] : [FBFuture futureWithResult:@{}],
    ]]
    onQueue:self.target.workQueue map:^(NSArray<id> *results) {
      NSArray<FBInstalledApplication *> *installed = results[0];
      NSDictionary<NSString *, NSNumber *> *running = results[1];
      NSMutableDictionary<FBInstalledApplication *, id> *listing = NSMutableDictionary.dictionary;
      for (FBInstalledApplication *application in installed) {
        listing[application] = running[application.bundle.identifier] ?: NSNull.null;
      }
      return listing;
    }];
}

- (FBFuture<FBInstalledArtifact *> *)install_app_file_path:(NSString *)filePath make_debuggable:(BOOL)makeDebuggable override_modification_time:(BOOL)overrideModificationTime
{
  // Use .app directly, or extract an .ipa
  if ([FBBundleDescriptor isApplicationAtPath:filePath]) {
    NSError *error = nil;
    FBBundleDescriptor *bundleDescriptor = [FBBundleDescriptor bundleFromPath:filePath error:&error];
    if (!bundleDescriptor) {
      return [FBFuture futureWithError:error];
    }
    return [self installAppBundle:[FBFutureContext futureContextWithResult:bundleDescriptor] makeDebuggable:makeDebuggable];
  } else {
    return [self installExtractedApp:[self.temporaryDirectory withArchiveExtractedFromFile:filePath overrideModificationTime:overrideModificationTime] makeDebuggable:makeDebuggable];
  }
}

- (FBFuture<FBInstalledArtifact *> *)install_app_stream:(FBProcessInput *)input compression:(FBCompressionFormat)compression make_debuggable:(BOOL)makeDebuggable override_modification_time:(BOOL)overrideModificationTime
{
  return [self installExtractedApp:[self.temporaryDirectory withArchiveExtractedFromStream:input compression:compression overrideModificationTime:overrideModificationTime] makeDebuggable:makeDebuggable];
}

- (FBFuture<FBInstalledArtifact *> *)install_xctest_app_file_path:(NSString *)filePath skipSigningBundles:(BOOL)skipSigningBundles
{
  return [self installXctestFilePath:[FBFutureContext futureContextWithFuture:[FBFuture futureWithResult:[NSURL fileURLWithPath:filePath]]] skipSigningBundles:skipSigningBundles];
}

- (FBFuture<FBInstalledArtifact *> *)install_xctest_app_stream:(FBProcessInput *)stream skipSigningBundles:(BOOL)skipSigningBundles
{
  return [self installXctest:[self.temporaryDirectory withArchiveExtractedFromStream:stream compression:FBCompressionFormatGZIP] skipSigningBundles:skipSigningBundles];
}

- (FBFuture<FBInstalledArtifact *> *)install_dylib_file_path:(NSString *)filePath
{
  return [self installFile:[FBFutureContext futureContextWithFuture:[FBFuture futureWithResult:[NSURL fileURLWithPath:filePath]]] intoStorage:self.storageManager.dylib];
}

- (FBFuture<FBInstalledArtifact *> *)install_dylib_stream:(FBProcessInput *)input name:(NSString *)name
{
  return [self installFile:[self.temporaryDirectory withGzipExtractedFromStream:input name:name] intoStorage:self.storageManager.dylib];
}

- (FBFuture<FBInstalledArtifact *> *)install_framework_file_path:(NSString *)filePath
{
  return [self installBundle:[FBFutureContext futureContextWithFuture:[FBFuture futureWithResult:[NSURL fileURLWithPath:filePath]]] intoStorage:self.storageManager.framework];
}

- (FBFuture<FBInstalledArtifact *> *)install_framework_stream:(FBProcessInput *)input
{
  return [self installBundle:[self.temporaryDirectory withArchiveExtractedFromStream:input compression:FBCompressionFormatGZIP] intoStorage:self.storageManager.framework];
}

- (FBFuture<FBInstalledArtifact *> *)install_dsym_file_path:(NSString *)filePath linkTo:(nullable FBDsymInstallLinkToBundle *)linkTo
{
  return [self installAndLinkDsym:[FBFutureContext futureContextWithFuture:[FBFuture futureWithResult:[NSURL fileURLWithPath:filePath]]] intoStorage:self.storageManager.dsym linkTo:linkTo];
}

- (FBFuture<FBInstalledArtifact *> *)install_dsym_stream:(FBProcessInput *)input compression:(FBCompressionFormat)compression linkTo:(nullable FBDsymInstallLinkToBundle *)linkTo
{
  return [self installAndLinkDsym:[self dsymDirnameFromUnzipDir:[self.temporaryDirectory withArchiveExtractedFromStream:input compression:compression]] intoStorage:self.storageManager.dsym linkTo:linkTo];
}

#pragma mark Public Methods

- (FBFuture<NSData *> *)take_screenshot:(FBScreenshotFormat)format
{
  return [[self
    screenshotCommands]
    onQueue:self.target.workQueue fmap:^(id<FBScreenshotCommands> commands) {
        return [commands takeScreenshot:format];
    }];
}

- (FBFuture<id> *)accessibility_info_at_point:(nullable NSValue *)value nestedFormat:(BOOL)nestedFormat
{
  return [[self
    accessibilityCommands]
    onQueue:self.target.workQueue fmap:^ FBFuture * (id<FBAccessibilityCommands> commands) {
      if (value) {
        return [commands accessibilityElementAtPoint:value.pointValue nestedFormat:nestedFormat];
      } else {
        return [commands accessibilityElementsWithNestedFormat:nestedFormat];
      }
    }];
}

- (FBFuture<NSNull *> *)add_media:(NSArray<NSURL *> *)filePaths
{
  return [self.mediaCommands
    onQueue:self.target.asyncQueue fmap:^FBFuture *(id<FBSimulatorMediaCommands> commands) {
      return [commands addMedia:filePaths];
    }];
}

- (FBFuture<NSNull *> *)set_location:(double)latitude longitude:(double)longitude
{
  id<FBLocationCommands> commands = (id<FBLocationCommands>) self.target;
  if (![commands conformsToProtocol:@protocol(FBLocationCommands)]) {
    return [[FBIDBError
      describeFormat:@"%@ does not conform to FBLocationCommands", commands]
      failFuture];
  }
  return [commands overrideLocationWithLongitude:longitude latitude:latitude];
}

- (FBFuture<NSNull *> *)clear_keychain
{
  return [self.keychainCommands
    onQueue:self.target.workQueue fmap:^FBFuture *(id<FBSimulatorKeychainCommands> commands) {
      return [commands clearKeychain];
    }];
}

- (FBFuture<NSNull *> *)approve:(NSSet<FBTargetSettingsService> *)services for_application:(NSString *)bundleID
{
  return [self.settingsCommands
    onQueue:self.target.workQueue fmap:^FBFuture *(id<FBSimulatorSettingsCommands> commands) {
      return [commands grantAccess:[NSSet setWithObject:bundleID] toServices:services];
    }];
}

- (FBFuture<NSNull *> *)revoke:(NSSet<FBTargetSettingsService> *)services for_application:(NSString *)bundleID
{
  return [self.settingsCommands
    onQueue:self.target.workQueue fmap:^FBFuture *(id<FBSimulatorSettingsCommands> commands) {
      return [commands revokeAccess:[NSSet setWithObject:bundleID] toServices:services];
    }];
}

- (FBFuture<NSNull *> *)approve_deeplink:(NSString *)scheme for_application:(NSString *)bundleID
{
  return [self.settingsCommands
  onQueue:self.target.workQueue fmap:^FBFuture *(id<FBSimulatorSettingsCommands> commands) {
    return [commands grantAccess:[NSSet setWithObject:bundleID] toDeeplink:scheme];
  }];
}

- (FBFuture<NSNull *> *)revoke_deeplink:(NSString *)scheme for_application:(NSString *)bundleID
{
  return [self.settingsCommands
  onQueue:self.target.workQueue fmap:^FBFuture *(id<FBSimulatorSettingsCommands> commands) {
    return [commands revokeAccess:[NSSet setWithObject:bundleID] toDeeplink:scheme];
  }];
}

- (FBFuture<NSNull *> *)open_url:(NSString *)url
{
  return [self.lifecycleCommands
    onQueue:self.target.workQueue fmap:^FBFuture *(id<FBSimulatorLifecycleCommands> commands) {
      return [commands openURL:[NSURL URLWithString:url]];
    }];
}

- (FBFuture<NSNull *> *)remove_all_storage_and_clear_keychain
{
  NSError *error = nil;
  if (![self.storageManager clean:&error]) {
    return [FBFuture futureWithError:error];
  }
  return [self clear_keychain];
}

- (FBFuture<NSNull *> *)uninstall_all_applications
{
  return [[self list_apps:NO] onQueue:self.target.workQueue fmap:^FBFuture<NSNull *> *(NSDictionary<FBInstalledApplication *,id> *apps) {
    NSMutableArray<FBFuture<NSNull *> *> *uninstall_futures = NSMutableArray.array;
    for (FBInstalledApplication *app in apps) {
      if (app.installType == FBApplicationInstallTypeUser){
        [uninstall_futures addObject:[[self kill_application:app.bundle.identifier] onQueue:self.target.workQueue fmap:^FBFuture<NSNull *> *(id _) {
          return [self uninstall_application:app.bundle.identifier];
        }]];
      }
    }
    return [FBFuture futureWithFutures:uninstall_futures];
  }];
}

- (FBFuture<NSNull *> *)clean
{
  if (self.target.state == FBiOSTargetStateShutdown) {
    return [self remove_all_storage_and_clear_keychain];
  }

  return [[self uninstall_all_applications] onQueue:self.target.workQueue fmap:^FBFuture<NSNull *> *(id _) {
    return [self remove_all_storage_and_clear_keychain];
  }];
}

- (FBFuture<NSNull *> *)focus
{
  return [self.lifecycleCommands
    onQueue:self.target.workQueue fmap:^FBFuture *(id<FBSimulatorLifecycleCommands> commands) {
      return [commands focus];
    }];
}

- (FBFuture<NSNull *> *)update_contacts:(NSData *)dbTarData
{
  return [[self.temporaryDirectory
    withArchiveExtracted:dbTarData]
    onQueue:self.target.workQueue pop:^(NSURL *tempDirectory) {
      return [self.settingsCommands onQueue:self.target.workQueue fmap:^FBFuture *(id<FBSimulatorSettingsCommands> commands) {
        return [commands updateContacts:tempDirectory.path];
      }];
    }];
}

- (FBFuture<NSArray<id<FBXCTestDescriptor>> *> *)list_test_bundles
{
  return [FBFuture onQueue:self.target.workQueue resolve:^{
    NSError *error;
    NSArray<id<FBXCTestDescriptor>> *testDescriptors = [self.storageManager.xctest listTestDescriptorsWithError:&error];
    if (testDescriptors == nil) {
      return [FBFuture futureWithError:error];
    }
    return [FBFuture futureWithResult:testDescriptors];
  }];
}

// Some Mac tests are big that dlopen might take long
static const NSTimeInterval ListTestBundleTimeout = 180.0;

- (FBFuture<NSArray<NSString *> *> *)list_tests_in_bundle:(NSString *)bundleID with_app:(NSString *)appPath
{
  if ([appPath isEqualToString:@""]) {
    appPath = nil;
  }

  if ([self.storageManager.application.persistedBundleIDs containsObject:appPath]) {
    // appPath is actually an app bundle ID
    appPath = self.storageManager.application.persistedBundles[appPath].path;
  }

  return [FBFuture
    onQueue:self.target.workQueue resolve:^ FBFuture<NSArray<NSString *> *> * {
      NSError *error = nil;
      id<FBXCTestDescriptor> testDescriptor = [self.storageManager.xctest testDescriptorWithID:bundleID error:&error];
      if (!testDescriptor) {
        return [FBFuture futureWithError:error];
      }
      id<FBXCTestExtendedCommands> commands = (id<FBXCTestExtendedCommands>) self.target;
      if (![commands conformsToProtocol:@protocol(FBXCTestExtendedCommands)]) {
        return [[FBIDBError
          describeFormat:@"%@ does not conform to FBXCTestExtendedCommands", commands]
          failFuture];
      }
      return [commands listTestsForBundleAtPath:testDescriptor.url.path timeout:ListTestBundleTimeout withAppAtPath:appPath];
    }];
}

- (FBFuture<NSNull *> *)uninstall_application:(NSString *)bundleID
{
  return [self.target uninstallApplicationWithBundleID:bundleID];
}

- (FBFuture<NSNull *> *)kill_application:(NSString *)bundleID
{
  return [[self.target killApplicationWithBundleID:bundleID] fallback:NSNull.null];
}

- (FBFuture<id<FBLaunchedApplication>> *)launch_app:(FBApplicationLaunchConfiguration *)configuration
{
  NSMutableDictionary<NSString *, NSString *> *replacements = NSMutableDictionary.dictionary;
  [replacements addEntriesFromDictionary:self.storageManager.replacementMapping];
  [replacements addEntriesFromDictionary:self.target.replacementMapping];
  NSDictionary<NSString *, NSString *> *environment = [self applyEnvironmentReplacements:configuration.environment replacements:replacements];

  FBApplicationLaunchConfiguration *derived = [[FBApplicationLaunchConfiguration alloc]
    initWithBundleID:configuration.bundleID
    bundleName:configuration.bundleName
    arguments:configuration.arguments
    environment:environment
    waitForDebugger:configuration.waitForDebugger
    io:configuration.io
    launchMode:configuration.launchMode];
  return [self.target launchApplication:derived];
}

- (NSDictionary<NSString *, NSString *> *)applyEnvironmentReplacements:(NSDictionary<NSString *, NSString *> *)environment replacements:(NSDictionary<NSString *, NSString *> *)replacements
{
  [self.logger logFormat:@"Original environment: %@", environment];
  [self.logger logFormat:@"Existing replacement mapping: %@", replacements];
  NSMutableDictionary<NSString *, NSString *> *interpolatedEnvironment = [NSMutableDictionary dictionaryWithCapacity:environment.count];
  for (NSString *name in environment.allKeys) {
    NSString *value = environment[name];
    for (NSString *interpolationName in replacements.allKeys) {
      NSString *interpolationValue = replacements[interpolationName];
      value = [value stringByReplacingOccurrencesOfString:interpolationName withString:interpolationValue];
    }
    interpolatedEnvironment[name] = value;
  }
  [self.logger logFormat:@"Interpolated environment: %@", interpolatedEnvironment];
  return interpolatedEnvironment;
}

- (FBFuture<FBIDBTestOperation *> *)xctest_run:(FBXCTestRunRequest *)request reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  return [request startWithBundleStorageManager:self.storageManager.xctest target:self.target reporter:reporter logger:logger temporaryDirectory:self.temporaryDirectory];
}

- (FBFuture<id<FBDebugServer>> *)debugserver_start:(NSString *)bundleID
{
  id<FBDebuggerCommands> commands = (id<FBDebuggerCommands>) self.target;
  if (![commands conformsToProtocol:@protocol(FBDebuggerCommands)]) {
    return [[FBControlCoreError
      describeFormat:@"Target doesn't conform to FBDebuggerCommands protocol %@", commands]
      failFuture];
  }

  return [[[self
    debugserver_prepare:bundleID]
    onQueue:self.target.workQueue fmap:^(FBBundleDescriptor *application) {
      return [commands launchDebugServerForHostApplication:application port:self.debugserverPort];
    }]
    onQueue:self.target.workQueue doOnResolved:^(id<FBDebugServer> debugServer) {
      self.debugServer = debugServer;
    }];
}

- (FBFuture<id<FBDebugServer>> *)debugserver_status
{
  return [FBFuture
    onQueue:self.target.workQueue resolve:^{
      id<FBDebugServer> debugServer = self.debugServer;
      if (!debugServer) {
        return [[FBControlCoreError
          describe:@"No debug server running"]
          failFuture];
      }
      return [FBFuture futureWithResult:debugServer];
    }];
}

- (FBFuture<id<FBDebugServer>> *)debugserver_stop
{
  return [[[self
    debugserver_status]
    onQueue:self.target.workQueue fmap:^(id<FBDebugServer> debugServer) {
      return [[self.debugServer.completed cancel] mapReplace:debugServer];
    }]
    onQueue:self.target.workQueue doOnResolved:^(id _) {
      self.debugServer = nil;
    }];
}

- (FBFuture<NSArray<FBCrashLogInfo *> *> *)crash_list:(NSPredicate *)predicate
{
  return [[self.target
    crashes:predicate useCache:NO]
    onQueue:self.target.asyncQueue map:^(NSArray<FBCrashLogInfo *> *crashes) {
      return crashes;
    }];
}

- (FBFuture<FBCrashLog *> *)crash_show:(NSPredicate *)predicate
{
  return [[self.target
    crashes:predicate useCache:YES]
    onQueue:self.target.asyncQueue fmap:^(NSArray<FBCrashLogInfo *> *crashes) {
      if (crashes.count > 1) {
         return [[FBIDBError
          describeFormat:@"More than one crash log matching %@", predicate]
          failFuture];
      }
      if (crashes.count == 0) {
        return [[FBIDBError
          describeFormat:@"No crashes matching %@", predicate]
          failFuture];
      }
      NSError *error = nil;
      FBCrashLog *log = [crashes.firstObject obtainCrashLogWithError:&error];
      if (!log) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:log];
    }];
}

- (FBFuture<NSArray<FBCrashLogInfo *> *> *)crash_delete:(NSPredicate *)predicate
{
  return [[self.target
    pruneCrashes:predicate]
    onQueue:self.target.asyncQueue map:^(NSArray<FBCrashLogInfo *> *crashes) {
      return crashes;
    }];
}

- (FBFuture<FBBundleDescriptor *> *)debugserver_prepare:(NSString *)bundleID
{
  return [FBFuture
    onQueue:self.target.workQueue resolve:^ FBFuture<FBBundleDescriptor *> * {
      if (self.debugServer) {
        return [[FBControlCoreError
          describeFormat:@"Debug server is already running"]
          failFuture];
      }
      NSDictionary<NSString *, FBBundleDescriptor *> *persisted = self.storageManager.application.persistedBundles;
      FBBundleDescriptor *bundle = persisted[bundleID];
      if (!bundle) {
        return [[FBIDBError
          describeFormat:@"%@ not persisted application and is therefore not debuggable. Suitable applications: %@", bundleID, [FBCollectionInformation oneLineDescriptionFromArray:persisted.allKeys]]
          failFuture];
      }

      return [FBFuture futureWithResult:bundle];
  }];
}

- (FBFuture<id<FBLogOperation>> *)tail_companion_logs:(id<FBDataConsumer>)consumer
{
  return [self.logger tailToConsumer:consumer];
}

- (FBFuture<NSDictionary<NSString *, id> *> *)diagnostic_information
{
  id<FBDiagnosticInformationCommands> commands = (id<FBDiagnosticInformationCommands>) self.target;
  if (![commands conformsToProtocol:@protocol(FBDiagnosticInformationCommands)]) {
    // Don't fail, just return empty.
    return [FBFuture futureWithResult:@{}];
  }
  return [commands fetchDiagnosticInformation];
}

- (FBFuture<NSNull *> *)hid:(id<FBSimulatorHIDEvent>)event
{
  return [self.connectToHID
    onQueue:self.target.workQueue fmap:^FBFuture *(FBSimulatorHID *hid) {
      return [event performOnHID:hid];
    }];
}

- (FBFuture<NSNull *> *)set_hardware_keyboard_enabled:(BOOL)enabled
{
  return [[self
    settingsCommands]
    onQueue:self.target.workQueue fmap:^(id<FBSimulatorSettingsCommands> commands) {
      return [commands setHardwareKeyboardEnabled:enabled];
    }];
}

- (FBFuture<NSNull *> *)set_preference:(NSString *)name value:(NSString *)value type:(nullable NSString *)type domain:(nullable NSString *)domain
{
  return [[self
    settingsCommands]
    onQueue:self.target.workQueue fmap:^(id<FBSimulatorSettingsCommands> commands) {
    return [commands setPreference:name value:value type:type domain:domain];
    }];
}

- (FBFuture<NSString *> *)get_preference:(NSString *)name domain:(nullable NSString *)domain
{
  return [[self
    settingsCommands]
    onQueue:self.target.workQueue fmap:^(id<FBSimulatorSettingsCommands> commands) {
    return [commands getCurrentPreference:name domain:domain];
    }];
}

- (FBFuture<NSNull *> *)set_locale_with_identifier:(NSString *)identifier
{
  return [[self
    settingsCommands]
    onQueue:self.target.workQueue fmap:^(id<FBSimulatorSettingsCommands> commands) {
    return [commands setPreference:@"AppleLocale" value:identifier type:nil domain:nil];
    }];
}

- (FBFuture<NSString *> *)get_current_locale_identifier
{
  return [[self
    settingsCommands]
    onQueue:self.target.workQueue fmap:^(id<FBSimulatorSettingsCommands> commands) {
      return [commands getCurrentPreference:@"AppleLocale" domain:nil];
    }];
}

- (NSArray<NSString *> *)list_locale_identifiers
{
  return NSLocale.availableLocaleIdentifiers;
}

#pragma mark File Commands

- (FBFuture<NSNull *> *)move_paths:(NSArray<NSString *> *)originPaths to_path:(NSString *)destinationPath containerType:(NSString *)containerType
{
  return [[self
    applicationDataContainerCommands:containerType]
    onQueue:self.target.workQueue pop:^(id<FBFileContainer> container) {
      NSMutableArray<FBFuture<NSNull *> *> *futures = NSMutableArray.array;
      for (NSString *originPath in originPaths) {
        [futures addObject:[container moveFrom:originPath to:destinationPath]];
      }
      return [[FBFuture futureWithFutures:futures] mapReplace:NSNull.null];
    }];
}

- (FBFuture<NSNull *> *)push_file_from_tar:(NSData *)tarData to_path:(NSString *)destinationPath containerType:(NSString *)containerType
{
  return [[self.temporaryDirectory
    withArchiveExtracted:tarData]
    onQueue:self.target.workQueue pop:^FBFuture *(NSURL *extractionDirectory) {
      NSError *error;
      NSArray<NSURL *> *paths = [NSFileManager.defaultManager contentsOfDirectoryAtURL:extractionDirectory includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:0 error:&error];
      if (!paths) {
        return [FBFuture futureWithError:error];
      }
      return [self push_files:paths to_path:destinationPath containerType:containerType];
   }];
}

- (FBFuture<NSNull *> *)push_files:(NSArray<NSURL *> *)paths to_path:(NSString *)destinationPath containerType:(NSString *)containerType
{
  return [FBFuture
    onQueue:self.target.asyncQueue resolve:^FBFuture<NSNull *> *{
      return [[self
        applicationDataContainerCommands:containerType]
        onQueue:self.target.workQueue pop:^FBFuture *(id<FBFileContainer> container) {
          NSMutableArray<FBFuture<NSNull *> *> *futures = NSMutableArray.array;
          for (NSURL *originPath in paths) {
            [futures addObject:[container copyFromHost:originPath.path toContainer:destinationPath]];
          }
          return [[FBFuture futureWithFutures:futures] mapReplace:NSNull.null];
        }];
  }];
}

- (FBFuture<NSString *> *)pull_file_path:(NSString *)path destination_path:(NSString *)destinationPath containerType:(NSString *)containerType
{
  return [[self
    applicationDataContainerCommands:containerType]
    onQueue:self.target.workQueue pop:^FBFuture *(id<FBFileContainer> commands) {
      return [commands copyFromContainer:path toHost:destinationPath];
    }];
}

- (FBFuture<NSData *> *)pull_file:(NSString *)path containerType:(NSString *)containerType
{
  __block NSString *tempPath;

  return [[[self.temporaryDirectory
    withTemporaryDirectory]
    onQueue:self.target.workQueue pend:^(NSURL *url) {
      tempPath = [url.path stringByAppendingPathComponent:path.lastPathComponent];
      return [[self
        applicationDataContainerCommands:containerType]
        onQueue:self.target.workQueue pop:^(id<FBFileContainer> container) {
          return [container copyFromContainer:path toHost:tempPath];
        }];
    }]
    onQueue:self.target.workQueue pop:^(id _) {
      return [FBArchiveOperations createGzippedTarDataForPath:tempPath queue:self.target.workQueue logger:self.target.logger];
    }];
}

- (FBFuture<FBFuture<NSNull *> *> *)tail:(NSString *)path to_consumer:(id<FBDataConsumer>)consumer in_container:(nullable NSString *)containerType
{
  return [[self
    applicationDataContainerCommands:containerType]
    onQueue:self.target.workQueue pop:^(id<FBFileContainer> container) {
      return [container tail:path toConsumer:consumer];
    }];
}

- (FBFuture<NSNull *> *)create_directory:(NSString *)directoryPath containerType:(NSString *)containerType
{
  return [[self
    applicationDataContainerCommands:containerType]
    onQueue:self.target.workQueue pop:^(id<FBFileContainer> targetApplicationData) {
      return [targetApplicationData createDirectory:directoryPath];
    }];
}

- (FBFuture<NSNull *> *)remove_paths:(NSArray<NSString *> *)paths containerType:(NSString *)containerType
{
  return [[self
    applicationDataContainerCommands:containerType]
    onQueue:self.target.workQueue pop:^FBFuture *(id<FBFileContainer> container) {
      NSMutableArray<FBFuture<NSNull *> *> *futures = NSMutableArray.array;
      for (NSString *path in paths) {
        [futures addObject:[container remove:path]];
      }
      return [[FBFuture futureWithFutures:futures] mapReplace:NSNull.null];
    }];
}

- (FBFuture<NSArray<NSString *> *> *)list_path:(NSString *)path containerType:(NSString *)containerType
{
  return [[self
    applicationDataContainerCommands:containerType]
    onQueue:self.target.workQueue pop:^FBFuture *(id<FBFileContainer> container) {
      return [container contentsOfDirectory:path];
    }];
}

- (FBFuture<NSDictionary<NSString *, NSArray<NSString *> *> *> *)list_paths:(NSArray<NSString *> *)paths containerType:(NSString *)containerType
{
  return [[[self
    applicationDataContainerCommands:containerType]
    onQueue:self.target.workQueue pop:^FBFuture *(id<FBFileContainer> container) {
      NSMutableArray<FBFuture<NSArray<NSString *> *> *> *futures = NSMutableArray.array;
      for (NSString *path in paths) {
        [futures addObject:[container contentsOfDirectory:path]];
      }
      return [FBFuture futureWithFutures:futures];
    }]
    onQueue:self.target.asyncQueue map:^ (NSArray<NSArray<NSString *> *> *listings) {
      // Dictionary is constructed by attaching paths for ordering within array.
      return [NSDictionary dictionaryWithObjects:listings forKeys:paths];
    }];
}

- (FBFuture<FBProcess<id, id<FBDataConsumer>, NSString *> *> *) dapServerWithPath:(NSString *)dapPath stdIn:(FBProcessInput *)stdIn stdOut:(id<FBDataConsumer>)stdOut
{
  id<FBDapServerCommand> commands = (id<FBDapServerCommand>) self.target;
  if (![commands conformsToProtocol:@protocol(FBDapServerCommand)]) {
    return [[FBControlCoreError
      describeFormat:@"Target doesn't conform to FBDapServerCommand protocol %@", commands]
      failFuture];
  }

  return [commands launchDapServer:dapPath stdIn:stdIn stdOut:stdOut];
}


#pragma mark Private Methods

- (FBFutureContext<id<FBFileContainer>> *)applicationDataContainerCommands:(NSString *)containerType
{
  if ([containerType isEqualToString:FBFileContainerKindCrashes]) {
    return [self.target crashLogFiles];
  }
  id<FBFileCommands> commands = (id<FBFileCommands>) self.target;
  if (![commands conformsToProtocol:@protocol(FBFileCommands)]) {
    return [[FBControlCoreError
      describeFormat:@"Target doesn't conform to FBFileCommands protocol %@", commands]
      failFutureContext];
  }
  if ([containerType isEqualToString:FBFileContainerKindApplication]) {
    return [commands fileCommandsForApplicationContainers];
  }
  if ([containerType isEqualToString:FBFileContainerKindGroup]) {
    return [commands fileCommandsForGroupContainers];
  }
  if ([containerType isEqualToString:FBFileContainerKindMedia]) {
    return [commands fileCommandsForMediaDirectory];
  }
  if ([containerType isEqualToString:FBFileContainerKindRoot]) {
    return [commands fileCommandsForRootFilesystem];
  }
  if ([containerType isEqualToString:FBFileContainerKindProvisioningProfiles]) {
    return [commands fileCommandsForProvisioningProfiles];
  }
  if ([containerType isEqualToString:FBFileContainerKindMDMProfiles]) {
    return [commands fileCommandsForMDMProfiles];
  }
  if ([containerType isEqualToString:FBFileContainerKindSpringboardIcons]) {
    return [commands fileCommandsForSpringboardIconLayout];
  }
  if ([containerType isEqualToString:FBFileContainerKindWallpaper]) {
    return [commands fileCommandsForWallpaper];
  }
  if ([containerType isEqualToString:FBFileContainerKindDiskImages]) {
    return [commands fileCommandsForDiskImages];
  }
  if ([containerType isEqualToString:FBFileContainerKindSymbols]) {
    return [commands fileCommandsForSymbols];
  }
  if ([containerType isEqualToString:FBFileContainerKindAuxillary]) {
    return [commands fileCommandsForAuxillary];
  }
  if ([containerType isEqualToString:FBFileContainerKindXctest]) {
    return [FBFutureContext futureContextWithResult:self.storageManager.xctest.asFileContainer];
  }
  if ([containerType isEqualToString:FBFileContainerKindDylib]) {
    return [FBFutureContext futureContextWithResult:self.storageManager.dylib.asFileContainer];
  }
  if ([containerType isEqualToString:FBFileContainerKindDsym]) {
    return [FBFutureContext futureContextWithResult:self.storageManager.dsym.asFileContainer];
  }
  if ([containerType isEqualToString:FBFileContainerKindFramework]) {
    return [FBFutureContext futureContextWithResult:self.storageManager.framework.asFileContainer];
  }
  if (containerType == nil || containerType.length == 0) {
    // The Default for no, or null container for back-compat.
    return [self.target isKindOfClass:FBDevice.class] ? [commands fileCommandsForMediaDirectory] : [commands fileCommandsForRootFilesystem];
  }
  return [commands fileCommandsForContainerApplication:containerType];
}


- (FBFuture<id<FBScreenshotCommands>> *)screenshotCommands
{
  id<FBScreenshotCommands> commands = (id<FBScreenshotCommands>) self.target;
  if (![commands conformsToProtocol:@protocol(FBScreenshotCommands)]) {
    return [[FBIDBError
       describeFormat:@"Target doesn't conform to FBScreenshotCommands protocol %@", self.target]
      failFuture];
  }
  return [FBFuture futureWithResult:commands];
}

- (FBFuture<id<FBSimulatorLifecycleCommands>> *)lifecycleCommands
{
  id<FBSimulatorLifecycleCommands> commands = (id<FBSimulatorLifecycleCommands>) self.target;
  if (![commands conformsToProtocol:@protocol(FBSimulatorLifecycleCommands)]) {
    return [[FBIDBError
      describeFormat:@"Target doesn't conform to FBSimulatorLifecycleCommands protocol %@", self.target]
      failFuture];
  }
  return [FBFuture futureWithResult:commands];
}

- (FBFuture<id<FBSimulatorMediaCommands>> *)mediaCommands
{
  id<FBSimulatorMediaCommands> commands = (id<FBSimulatorMediaCommands>) self.target;
  if (![commands conformsToProtocol:@protocol(FBSimulatorMediaCommands)]) {
    return [[FBIDBError
      describeFormat:@"Target doesn't conform to FBSimulatorMediaCommands protocol %@", self.target]
      failFuture];
  }
  return [FBFuture futureWithResult:commands];
}

- (FBFuture<id<FBSimulatorKeychainCommands>> *)keychainCommands
{
  id<FBSimulatorKeychainCommands> commands = (id<FBSimulatorKeychainCommands>) self.target;
  if (![commands conformsToProtocol:@protocol(FBSimulatorKeychainCommands)]) {
    return [[FBIDBError
      describeFormat:@"Target doesn't conform to FBSimulatorKeychainCommands protocol %@", self.target]
      failFuture];
  }
  return [FBFuture futureWithResult:commands];
}

- (FBFuture<id<FBSimulatorSettingsCommands>> *)settingsCommands
{
  id<FBSimulatorSettingsCommands> commands = (id<FBSimulatorSettingsCommands>) self.target;
  if (![commands conformsToProtocol:@protocol(FBSimulatorSettingsCommands)]) {
    return [[FBIDBError
      describeFormat:@"Target doesn't conform to FBSimulatorSettingsCommands protocol %@", self.target]
      failFuture];
  }
  return [FBFuture futureWithResult:commands];
}

- (FBFuture<id<FBAccessibilityCommands>> *)accessibilityCommands
{
  id<FBAccessibilityCommands> commands = (id<FBAccessibilityCommands>) self.target;
  if (![commands conformsToProtocol:@protocol(FBAccessibilityCommands)]) {
    return [[FBIDBError
      describeFormat:@"Target doesn't conform to FBAccessibilityCommands protocol %@", self.target]
      failFuture];
  }
  return [FBFuture futureWithResult:commands];
}

- (FBFuture<FBSimulatorHID *> *)connectToHID
{
  return [[self
    lifecycleCommands]
    onQueue:self.target.workQueue fmap:^ FBFuture<FBSimulatorHID *> * (id<FBSimulatorLifecycleCommands> commands) {
      NSError *error = nil;
      if (![FBSimulatorControlFrameworkLoader.xcodeFrameworks loadPrivateFrameworks:self.target.logger error:&error]) {
        return [[FBIDBError
          describeFormat:@"SimulatorKit is required for HID interactions: %@", error]
          failFuture];
      }
      return [commands connectToHID];
    }];
}

- (FBFuture<FBInstalledArtifact *> *)installExtractedApp:(FBFutureContext<NSURL *> *)extractedAppContext makeDebuggable:(BOOL)makeDebuggable
{
  FBFutureContext<FBBundleDescriptor *> *bundleContext = [extractedAppContext
    onQueue:self.target.asyncQueue pend:^(NSURL *extractPath) {
      NSError *error = nil;
      FBBundleDescriptor *bundleDescriptor = [FBBundleDescriptor findAppPathFromDirectory:extractPath error:&error];
      if (!bundleDescriptor) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:bundleDescriptor];
    }];
  return [self installAppBundle:bundleContext makeDebuggable:makeDebuggable];
}

- (FBFuture<FBInstalledArtifact *> *)installAppBundle:(FBFutureContext<FBBundleDescriptor *> *)bundleContext makeDebuggable:(BOOL)makeDebuggable
{
  BOOL userDevelopmentAppIsRequired = [self.target isKindOfClass:FBDevice.class];

  return [bundleContext
    onQueue:self.target.asyncQueue pop:^(FBBundleDescriptor *appBundle){
      if (!appBundle) {
        return [FBFuture futureWithError:[FBControlCoreError errorForDescription:@"No app bundle could be extracted"]];
      }
      NSError *error = nil;
      if (![self.storageManager.application checkArchitecture:appBundle error:&error]) {
        return [FBFuture futureWithError:error];
      }
      return [[FBFuture
        futureWithFutures:@[
          [self.target installApplicationWithPath:appBundle.path],
          // TODO: currently we have to persist it even if app is not used for debugging
          // as installed apps are referenced from xctestrun files and expanded by idb
          // by using its own application storage. Fix this by replacing xctestrun
          // placeholders by app bundle paths instead
          [self.storageManager.application saveBundle:appBundle]
        ]]
        onQueue:self.target.asyncQueue fmap:^(NSArray<id> *tuple) {
          FBInstalledApplication *installedApp = tuple[0];
          if (makeDebuggable && installedApp.installType != FBApplicationInstallTypeUserDevelopment && userDevelopmentAppIsRequired) {
                return [[FBIDBError
                  describeFormat:@"Requested debuggable install of %@ but User Development signing is required", installedApp]
                  failFuture];
          }
          return [FBFuture futureWithResult:[[FBInstalledArtifact alloc] initWithName:appBundle.identifier uuid:appBundle.binary.uuid path:[NSURL fileURLWithPath:installedApp.bundle.path]]];
        }];
    }];
}

- (FBFuture<FBInstalledArtifact *> *)installXctest:(FBFutureContext<NSURL *> *)extractedXctest skipSigningBundles:(BOOL)skipSigningBundles
{
  return [extractedXctest
    onQueue:self.target.workQueue pop:^(NSURL *extractionDirectory) {
      return [self.storageManager.xctest saveBundleOrTestRunFromBaseDirectory:extractionDirectory skipSigningBundles:skipSigningBundles];
  }];
}

- (FBFuture<FBInstalledArtifact *> *)installXctestFilePath:(FBFutureContext<NSURL *> *)bundle skipSigningBundles:(BOOL)skipSigningBundles
{
  return [bundle
    onQueue:self.target.workQueue pop:^(NSURL *xctestURL) {
      return [self.storageManager.xctest saveBundleOrTestRun:xctestURL skipSigningBundles:skipSigningBundles];
    }];
}

- (FBFuture<FBInstalledArtifact *> *)installFile:(FBFutureContext<NSURL *> *)extractedFileContext intoStorage:(FBFileStorage *)storage
{
  return [extractedFileContext
    onQueue:self.target.workQueue pop:^(NSURL *extractedFile) {
      NSError *error = nil;
      FBInstalledArtifact *artifact = [storage saveFile:extractedFile error:&error];
      if (!artifact) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:artifact];
    }];
}

// To navigate directly to the dSYM directory instead of the parent tmp directory
// created while unzipping
- (FBFutureContext<NSURL *> *)dsymDirnameFromUnzipDir:(FBFutureContext<NSURL *> *)extractedFileContext {
  return [extractedFileContext
    onQueue:self.target.workQueue pend:^(NSURL *parentDir) {
    NSError *error = nil;
    NSArray<NSURL *> *subDirs = [NSFileManager.defaultManager contentsOfDirectoryAtURL:parentDir includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:0 error:&error];
    if (!subDirs) {
      return [FBFuture futureWithError:error];
    }
    if ([subDirs count] != 1) {
      // if more than one dSYM is found
      // then we treat the parent dir as the dSYM directory
      return [FBFuture futureWithResult:parentDir];
    }
    return [FBFuture futureWithResult:subDirs[0]];
  }];
}

// Will install the dsym under standard dsym location
// if linkTo is passed:
// after installation it will create a symlink in the bundle container
- (FBFuture<FBInstalledArtifact *> *)installAndLinkDsym:(FBFutureContext<NSURL *> *)extractedFileContext intoStorage:(FBFileStorage *)storage linkTo:(nullable FBDsymInstallLinkToBundle *)linkTo
{
  return [extractedFileContext
    onQueue:self.target.workQueue pop:^(NSURL *extractionDir) {
      NSError *error = nil;
      FBInstalledArtifact *artifact = [storage saveFileInUniquePath:extractionDir error:&error];
      if (!artifact) {
        return [FBFuture futureWithError:error];
      }

      if (!linkTo) {
        return [FBFuture futureWithResult:artifact];
      }

      FBFuture<NSURL *> *future = nil;
      if (linkTo.bundle_type == FBDsymBundleTypeApp) {
        future = [[self.target installedApplicationWithBundleID:linkTo.bundle_id] onQueue:self.target.workQueue fmap:^(FBInstalledApplication *linkToApp) {
          [self.logger logFormat:@"Going to create a symlink for app bundle: %@", linkToApp.bundle.name];
          return [FBFuture futureWithResult:[NSURL fileURLWithPath:linkToApp.bundle.path]];
        }];
      } else {
        id<FBXCTestDescriptor> testDescriptor = [self.storageManager.xctest testDescriptorWithID:linkTo.bundle_id error:&error];
        [self.logger logFormat:@"Going to create a symlink for test bundle: %@", testDescriptor.name];
        future = [FBFuture futureWithResult:testDescriptor.url];
      }

      return [future onQueue:self.target.workQueue fmap:^(NSURL *bundlePath) {
                NSURL *bundleUrl = [bundlePath URLByDeletingLastPathComponent];
                NSURL *dsymURL = [bundleUrl URLByAppendingPathComponent:artifact.path.lastPathComponent];
                // delete a simlink if already exists
                // TODO: check if what we are deleting is a symlink
                [NSFileManager.defaultManager removeItemAtURL:dsymURL error:nil];
                [self.logger logFormat:@"Deleted a symlink for dsym if it already exists: %@", dsymURL];
                NSError *createLinkError = nil;
                if (![NSFileManager.defaultManager createSymbolicLinkAtURL:dsymURL withDestinationURL:artifact.path error:&createLinkError]){
                  return [FBFuture futureWithError:error];
                }
                [self.logger logFormat:@"Created a symlink for dsym from: %@ to %@", dsymURL, artifact.path];
                return [FBFuture futureWithResult:artifact];
            }];

  }];
}

- (FBFuture<FBInstalledArtifact *> *)installBundle:(FBFutureContext<NSURL *> *)extractedDirectoryContext intoStorage:(FBBundleStorage *)storage
{
  return [extractedDirectoryContext
    onQueue:self.target.workQueue pop:^ FBFuture<FBInstalledArtifact *> * (NSURL *extractedDirectory) {
      NSError *error = nil;
      FBBundleDescriptor *bundle = [FBStorageUtils bundleInDirectory:extractedDirectory error:&error];
      if (!bundle) {
        return [FBFuture futureWithError:error];
      }
      return [storage saveBundle:bundle];
    }];
}

- (FBFuture<NSNull *> *)sendPushNotificationForBundleID:(NSString *)bundleID jsonPayload:(NSString *)jsonPayload
{
  id<FBNotificationCommands> commands = (id<FBNotificationCommands>) self.target;
  if (![commands conformsToProtocol:@protocol(FBNotificationCommands)]) {
    return [[FBIDBError
      describeFormat:@"%@ does not conform to FBNotificationCommands", commands]
      failFuture];
  }
  return [commands sendPushNotificationForBundleID:bundleID jsonPayload:jsonPayload];
}

- (FBFuture<NSNull *> *)simulateMemoryWarning
{
  id<FBMemoryCommands> commands = (id<FBMemoryCommands>) self.target;
  if (![commands conformsToProtocol:@protocol(FBMemoryCommands)]) {
    return [[FBIDBError
             describeFormat:@"%@ does not conform to FBMemoryCommands", commands]
            failFuture];
  }
  return [commands simulateMemoryWarning];
}

@end
