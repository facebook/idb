/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBXCTestDescriptor;
@protocol FBControlCoreLogger;
@class FBBundleStorageManager;
@class FBDsymInstallLinkToBundle;
@class FBIDBLogger;
@class FBIDBPortsConfiguration;
@class FBIDBStorageManager;
@class FBIDBTestOperation;
@class FBInstalledArtifact;
@class FBSimulatorHIDEvent;
@class FBTemporaryDirectory;
@class FBXCTestRunRequest;

@protocol FBXCTestReporter;

extern FBFileContainerKind const FBFileContainerKindXctest;
extern FBFileContainerKind const FBFileContainerKindDylib;
extern FBFileContainerKind const FBFileContainerKindDsym;
extern FBFileContainerKind const FBFileContainerKindFramework;

@interface FBIDBCommandExecutor : NSObject

#pragma mark Initializers

/**
 The Designated Initializer.

 @param target the target to run against.
 @param storageManager storage for all bundles
 @param temporaryDirectory the temporary directory to use.
 @param debugserverPort will launch debug server at that port.
 @param logger a logger to log to.
 @return a new FBIDBCommandExecutor instance
 */
+ (instancetype)commandExecutorForTarget:(id<FBiOSTarget>)target storageManager:(FBIDBStorageManager *)storageManager temporaryDirectory:(FBTemporaryDirectory *)temporaryDirectory debugserverPort:(in_port_t)debugserverPort logger:(FBIDBLogger *)logger;

#pragma mark Properties

/**
 For storage of all bundles
 */
@property (nonatomic, strong, readonly) FBIDBStorageManager *storageManager;

/**
 The running debugserver
 */
@property (nonatomic, strong, nullable, readwrite) id<FBDebugServer> debugServer;

/**
 The Temporary Directory
 */
@property (nonatomic, strong, readonly) FBTemporaryDirectory *temporaryDirectory;

#pragma mark Public Methods

/**
 Lists Applications that are installed, optionally fetching process state.

 @param fetchProcessState YES if the process state should be fetched, NO otherwise.
 @return A future that resolves with the list of installed applications, mapped to NSNull | NSNumber of the running pid.
 */
- (FBFuture<NSDictionary<FBInstalledApplication *, id> *> *)list_apps:(BOOL)fetchProcessState;

/**
 Install an App via a File Path.

 @param filePath the path to a file on disk with the file.
 @param makeDebuggable whether the app should be installed in a debuggable state or not.
 @param overrideModificationTime if YES the archive contests' `mtime` will be ignored. Current timestamp will be used as mtime of extracted files/directories.
 @return A future that resolves with the App Bundle Id
 */
- (FBFuture<FBInstalledArtifact *> *)install_app_file_path:(NSString *)filePath make_debuggable:(BOOL)makeDebuggable override_modification_time:(BOOL)overrideModificationTime;

/**
 Install an App via a Data stream.

 @param input the input to pipe.
 @param compression the compression type to use
 @param makeDebuggable whether the app should be installed in a debuggable state or not.
 @param overrideModificationTime if YES the archive contests' `mtime` will be ignored. Current timestamp will be used as mtime of extracted files/directories.
 @return A future that resolves with the App Bundle Id
 */
- (FBFuture<FBInstalledArtifact *> *)install_app_stream:(FBProcessInput *)input compression:(FBCompressionFormat)compression make_debuggable:(BOOL)makeDebuggable override_modification_time:(BOOL)overrideModificationTime;

/**
 Installs an xctest bundle by file path.

 @param filePath the local file path of the xctest bundle
 @param skipSigningBundles pass true to skip signing xctest bundles.
 @return a Future that resolves with the xctest identifier.
 */
- (FBFuture<FBInstalledArtifact *> *)install_xctest_app_file_path:(NSString *)filePath skipSigningBundles:(BOOL)skipSigningBundles;

/**
 Installs an xctest bundle by a stream of tar data

 @param input a tar stream of the xctest data.
 @param skipSigningBundles pass true to skip signing xctest bundles.
 @return a Future that resolves with the xctest identifier.
 */
- (FBFuture<FBInstalledArtifact *> *)install_xctest_app_stream:(FBProcessInput *)input skipSigningBundles:(BOOL)skipSigningBundles;

/**
 Installs a dylib from a file path.

 @param filePath the path to a file on disk with the file.
 @return A future that resolves with the Dylib Name
 */
- (FBFuture<FBInstalledArtifact *> *)install_dylib_file_path:(NSString *)filePath;

/**
 Installs a dylib from a tar stream.

 @param input the input to pipe.
 @param name the name of the dylib
 @return A future that resolves with the Dylib Name
 */
- (FBFuture<FBInstalledArtifact *> *)install_dylib_stream:(FBProcessInput *)input name:(NSString *)name;

/**
 Installs a framework from a file path.

 @param filePath the path to a file on disk with the file.
 @return A future that resolves with the Dylib Name
 */
- (FBFuture<FBInstalledArtifact *> *)install_framework_file_path:(NSString *)filePath;

/**
 Installs a dylib from a tar stream.

 @param input the input to pipe.
 @return A future that resolves with the Dylib Name
 */
- (FBFuture<FBInstalledArtifact *> *)install_framework_stream:(FBProcessInput *)input;

/**
 Installs a dSYM from a file path.

 @param filePath the input to pipe.
 @param linkTo if specified installed dsym will be linked into bundle container.
 @return A future that resolves with the dSYM Name
 */
- (FBFuture<FBInstalledArtifact *> *)install_dsym_file_path:(NSString *)filePath linkTo:(nullable FBDsymInstallLinkToBundle *)linkTo;

/**
 Installs dSYM(s) from a zip stream.

 @param input the input to pipe.
 @param compression the compression type to use
 @param linkTo if specified installed dsym will be linked into bundle container.
 @return A future that resolves with the directory containing the dSYM(s)
 */
- (FBFuture<FBInstalledArtifact *> *)install_dsym_stream:(FBProcessInput *)input compression:(FBCompressionFormat)compression linkTo:(nullable FBDsymInstallLinkToBundle *)linkTo;

/**
 Takes a Screenshot

 @param format the format of the data.
 @return A Future, wrapping Data of the provided format.
 */
- (FBFuture<NSData *> *)take_screenshot:(FBScreenshotFormat)format;

/**
 Returns the accessibility info of a point on the screen

 @param point location on the screen (NSValue<NSPoint> *), returns info for the whole screen if nil
 @param nestedFormat YES if the legacy format should be used, NO otherwise.
 @return A Future that resolves with the accessibility info
 */
- (FBFuture<id> *)accessibility_info_at_point:(nullable NSValue *)point nestedFormat:(BOOL)nestedFormat;

/**
 Adds media files (photos, videos, ...) to the target

 @param filePaths local file paths to the media files
 @return A Future that resolves when complete
 */
- (FBFuture<NSNull *> *)add_media:(NSArray<NSURL *> *)filePaths;

/**
 Perform a hid event on the target

 @param event hid event to perform
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)hid:(FBSimulatorHIDEvent *)event;

/**
 Sets latitude and longitude of the Simulator.
 The behaviour of a directly-launched Simulator differs from Simulator.app slightly, in that the location isn't automatically set.
 Simulator.app will typically set a location from NSUserDefaults, so Applications will have a default location.

 @param latitude the latitude of the location.
 @param longitude the longitude of the location.
 @return a Future that resolves when the location has been sent.
 */
- (FBFuture<NSNull *> *)set_location:(double)latitude longitude:(double)longitude;

/**
 Cleans the keychain of the target.

 @return A future that resolves when the keychain has been cleared.
 */
- (FBFuture<NSNull *> *)clear_keychain;

/**
 Approves the given services for an app

 @param services services to approve
 @param bundleID app to approve services for
 @return a Future that resolves when complete.
 */
- (FBFuture<NSNull *> *)approve:(NSSet<FBTargetSettingsService> *)services for_application:(NSString *)bundleID;

/**
 Revokes the given services for an app

 @param services services to revoke
 @param bundleID app to revoke services for
 @return a Future that resolves when complete.
 */
- (FBFuture<NSNull *> *)revoke:(NSSet<FBTargetSettingsService> *)services for_application:(NSString *)bundleID;

/**
Approves the deeplink given a schema and app.
This allows to avoid the permission popup the first time we open a deeplink

@param scheme scheme of the deeplink url (the part before ":")
@param bundleID app to approve services for
@return a Future that resolves when complete.
*/
- (FBFuture<NSNull *> *)approve_deeplink:(NSString *)scheme for_application:(NSString *)bundleID;

/**
Revokes the deeplink given a schema and app.
This enables the permission popup the first time we open a deeplink

@param scheme scheme of the deeplink url (the part before ":")
@param bundleID app to revoke services for
@return a Future that resolves when complete.
*/
- (FBFuture<NSNull *> *)revoke_deeplink:(NSString *)scheme for_application:(NSString *)bundleID;

/**
 Open a url on the target

 @param url url to open
 @return a Future that resolves when complete.
 */
- (FBFuture<NSNull *> *)open_url:(NSString *)url;

/**
 Focus the simulator window

 @return a Future that resolves when complete.
 */
- (FBFuture<NSNull *> *)focus;

/**
 Update the contacts db on the device

 @param dbTarData a tar of the db file
 @return a Future that resolves when complete.
 */
- (FBFuture<NSNull *> *)update_contacts:(NSData *)dbTarData;

/**
 List the xctests installed

 @return a Future that resolves with an array of tests.
 */
- (FBFuture<NSArray<id<FBXCTestDescriptor>> *> *)list_test_bundles;

/**
 List the tests in an installed bundle

 @return a Future that resolves with names of tests in the bundle.
 */
- (FBFuture<NSArray<NSString *> *> *)list_tests_in_bundle:(NSString *)bundleID with_app:(nullable NSString *)appPath;

/**
 Uninstall an application

 @param bundleID bundle id of the application to uninstall
 @return a Future that resolves when complete.
 */
- (FBFuture<NSNull *> *)uninstall_application:(NSString *)bundleID;

/**
 Kill an application

 @param bundleID bundle id of the application to kill
 @return a Future that resolves when complete.
 */
- (FBFuture<NSNull *> *)kill_application:(NSString *)bundleID;

/**
 Launch an application

 @param configuration the configuration to use.
 @return a Future that resolves with the launched application.
 */
- (FBFuture<id<FBLaunchedApplication>> *)launch_app:(FBApplicationLaunchConfiguration *)configuration;

/**
 Lists Crashes according to a predicate

 @param predicate the predicate to use.
 @return a Future that resolves with the log info.
 */
- (FBFuture<NSArray<FBCrashLogInfo *> *> *)crash_list:(NSPredicate *)predicate;

/**
 Obtains crash log info

 @param predicate the predicate to use.
 @return a Future that resolves with the log.
 */
- (FBFuture<FBCrashLog *> *)crash_show:(NSPredicate *)predicate;

/**
 Deletes crash log info

 @param predicate the predicate to use.
 @return a Future that resolves with the logs of the deleted crashes.
 */
- (FBFuture<NSArray<FBCrashLogInfo *> *> *)crash_delete:(NSPredicate *)predicate;

/**
 Runs an xctest request

 @param request the request to run
 @param reporter the reporter to report to.
 @param logger the logger to log to.
 @return a Future that resolves with the xctest operation.
 */
- (FBFuture<FBIDBTestOperation *> *)xctest_run:(FBXCTestRunRequest *)request reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger;

/**
 Starts the debugserver

 @param bundleID the bundle id of the app to start for.
 @return a Future that resolves with the debugserver.
 */
- (FBFuture<id<FBDebugServer>> *)debugserver_start:(NSString *)bundleID;

/**
 Obtains the running debugserver.

 @return a Future that resolves with the debugserver.
 */
- (FBFuture<id<FBDebugServer>> *)debugserver_status;

/**
 Stops the running debugserver.

 @return a Future that resolves when the debugserver has stopped.
 */
- (FBFuture<id<FBDebugServer>> *)debugserver_stop;

/**
 Tails logs from the companion to a consumer

 @param consumer the consumer to use.
 @return a Future wrapping the log operation.
 */
- (FBFuture<id<FBLogOperation>> *)tail_companion_logs:(id<FBDataConsumer>)consumer;

/**
 Fetches diagnostic information

 @return a Future wrapping the diagnostic information
 */
- (FBFuture<NSDictionary<NSString *, id> *> *)diagnostic_information;

/**
 Sets the hardware keyboard

 @param enabled YES if enabled, NO if disabled.
 @return a Future that resolves when successful.
 */
- (FBFuture<NSNull *> *)set_hardware_keyboard_enabled:(BOOL)enabled;

/**
 Sets preference by name and value for a given domain. If domain not specified assumed to be Apple Global Domain

 @param name preference name
 @param value preference value
 @param type preference value type
 @param domain preference domain - optional
 @return a Future that resolves when successful.
 */
- (FBFuture<NSNull *> *)set_preference:(NSString *)name value:(NSString *)value type:(nullable NSString *)type domain:(nullable NSString *)domain;

/**
 Gets a preference value by its name and domain. If domain not specified assumed to be Apple Global Domain

 @param name preference name
 @param domain domain to search - optional
 @return a Future that resolves with the current preference value
 */
- (FBFuture<NSString *> *)get_preference:(NSString *)name domain:(nullable NSString *)domain;

/**
 Sets the Locale with a Locale Identifier.

 @param identifier the locale identifier.
 @return a Future that resolves when successful.
 */
- (FBFuture<NSNull *> *)set_locale_with_identifier:(NSString *)identifier;

/**
 Gets the Locale, by Locale Identifier

 @return a Future that resolves with the current locale identifier.
 */
- (FBFuture<NSString *> *)get_current_locale_identifier;

/**
 Lists all available Locale Identifiers

 @return a list of locale identifiers.
 */
- (NSArray<NSString *> *)list_locale_identifiers;

#pragma mark File Operations

/**
 Move data within the container to a different path

 @param originPaths relative paths to the container where data resides
 @param destinationPath relative path where the data will be moved to
 @param containerType the container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)move_paths:(NSArray<NSString *> *)originPaths to_path:(NSString *)destinationPath containerType:(nullable NSString *)containerType;

/**
 Push files to an applications container from a tar

 @param tarData file content
 @param destinationPath relative path to the container where the file will reside
 @param containerType the container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)push_file_from_tar:(NSData *)tarData to_path:(NSString *)destinationPath containerType:(nullable NSString *)containerType;

/**
 Push files to an applications container

 @param paths Paths of the files to push
 @param destinationPath relative path to the container where the file will reside
 @param containerType the container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)push_files:(NSArray<NSURL *> *)paths to_path:(NSString *)destinationPath containerType:(nullable NSString *)containerType;

/**
 Pull a file from an applications container

 @param path relative path to the container where file resides
 @param destinationPath path to write the file to.
 @param containerType the container.
 @return A future that resolves the path the file is copied to.
 */
- (FBFuture<NSString *> *)pull_file_path:(NSString *)path destination_path:(nullable NSString *)destinationPath containerType:(nullable NSString *)containerType;

/**
 Pull a file from an applications container

 @param path relative path to the container where file resides
 @param containerType the container.
 @return A future that resolves the content of that file.
 */
- (FBFuture<NSData *> *)pull_file:(NSString *)path containerType:(nullable NSString *)containerType;

/**
 Tails a file from the container
 */
- (FBFuture<FBFuture<NSNull *> *> *)tail:(NSString *)path to_consumer:(id<FBDataConsumer>)consumer in_container:(nullable NSString *)containerType;

/**
 Remove path within the container

 @param paths relative paths to the container where data resides
 @param containerType the container.
 @return A future that resolves when successful.
 */
- (FBFuture<NSNull *> *)remove_paths:(NSArray<NSString *> *)paths containerType:(nullable NSString *)containerType;

/**
 Lists path within the container. The api exists for backwards-compatibility

 @param path relative path to the container where data resides
 @param containerType the Bundle Identifier of the Container.
 @return A future that resolves with the list of files.
 */
- (FBFuture<NSArray<NSString *> *> *)list_path:(NSString *)path containerType:(nullable NSString *)containerType;

/**
 Lists path within the container

 @param paths relative path to the container where data resides
 @param containerType the Bundle Identifier of the Container.
 @return A future that resolves with a mapping of path to listing of paths within it.
 */
- (FBFuture<NSDictionary<NSString *, NSArray<NSString *> *> *> *)list_paths:(NSArray<NSString *> *)paths containerType:(nullable NSString *)containerType;

/**
 Creates a directory

 @param directoryPath the path of the directory.
 @param containerType the bundle id of the app.
 @return A Future that resolves when the directory is created.
 */
- (FBFuture<NSNull *> *)create_directory:(NSString *)directoryPath containerType:(NSString *)containerType;

/**
 Attemps to return the simulator back to a clean state by uninstalling everything

 @return null future
 */
- (FBFuture<NSNull *> *)clean;

/**
 Sends a notification

 @return null future
 */
- (FBFuture<NSNull *> *)sendPushNotificationForBundleID:(NSString *)bundleID jsonPayload:(NSString *)jsonPayload;

/**
 Spawn a dap protocol server from dapPath

 @param dapPath relative path to the root container where dap is installed
 @param stdIn where the dap process reads
 @param stdOut where the dap process writes
 @return A Future that resolves when the dap server is spawned. Returns the dap server process.
 */
- (FBFuture<FBIDBProcess<id, id<FBDataConsumer>, NSString *> *> *) dapServerWithPath:(NSString *)dapPath stdIn:(FBProcessInput *)stdIn stdOut:(id<FBDataConsumer>)stdOut;

/**
 Simulates a memory warning

 @return null future
 */
- (FBFuture<NSNull *> *)simulateMemoryWarning;

@end

NS_ASSUME_NONNULL_END
