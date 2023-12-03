/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBDeviceControl.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

#import <CompanionLib/FBIDBError.h>
#import <CompanionLib/FBIDBLogger.h>
#import <CompanionLib/FBiOSTargetProvider.h>
#import "FBiOSTargetStateChangeNotifier.h"
#import "FBiOSTargetDescription.h"
#import <CompanionLib/FBIDBStorageManager.h>
#import <CompanionLib/FBIDBCommandExecutor.h>

#import "idb-Swift.h"

const char *kUsageHelpMessage = "\
Usage: \n \
  Modes of operation, only one of these may be specified:\n\
    --udid UDID|mac|only       Launches a companion server for the specified UDID, 'mac' for a mac companion, or 'only' to run a companion for the only simulator/device available.\n\
    --boot UDID                Boots the simulator with the specified UDID.\n\
    --reboot UDID              Reboots the target with the specified UDID.\n\
    --shutdown UDID            Shuts down the target with the specified UDID.\n\
    --erase UDID               Erases the target with the specified UDID.\n\
    --clean UDID               Performs a soft reset to the specified UDID.\n\
    --delete UDID|all          Deletes the simulator with the specified UDID, or 'all' to delete all simulators in the set.\n\
    --create VALUE             Creates a simulator using the VALUE argument like \"iPhone X,iOS 12.4\"\n\
    --clone UDID               Clones a simulator by a given UDID\n\
    --clone-destination-set    A path to the destination device set in a clone operation, --device-set-path specifies the source simulator.\n\
    --recover ecid:ECID        Causes the targeted device ECID to enter recovery mode\n\
    --unrecover ecid:ECID      Causes the targeted device ECID to exit recovery mode\n\
    --activate ecid:ECID       Causes the device to activate\n\
    --notify PATH|stdout       Launches a companion notifier which will stream availability updates to the specified path, or stdout.\n\
    --forward UDID:PORT        Forwards the remote socket for the specified UDID to the specified remote PORT. Input and output is relayed via stdin/stdout\n\
    --list 1                   Lists all available devices and simulators in the current context. If Xcode is not correctly installed, only devices will be listed.\n\
    --version                  Writes companion version information to stdout.\n\
    --help                     Show this help message and exit.\n\
\n\
  Options:\n\
    --grpc-port PORT           Port to start the grpc companion server on (default: 10882).\n\
    --tls-cert-path PATH       If specified exposed GRPC server will be listening on a TLS enabled socket.\n\
    --grpc-domain-sock PATH    Unix Domain Socket path to start the companion server on, will superceed TCP binding via --grpc-port.\n\
    --debug-port PORT          Port to connect debugger on (default: 10881).\n\
    --log-file-path PATH       Path to write a log file to e.g ./output.log (default: logs to stdErr).\n\
    --log-level info|debug     The log level to use, 'debug' for a higher level of debugging 'info' for a lower level of logging (default 'debug').\n\
    --device-set-path PATH     Path to a custom Simulator device set.\n\
    --only FILTER_OPTION       If provided, will limit interaction to a subset of all available targets\n\
    --headless VALUE           If VALUE is a true value, the Simulator boot's lifecycle will be tied to the lifecycle of this invocation.\n\
    --verify-booted VALUE      If VALUE is a true value, will verify that the Simulator is in a known-booted state before --boot completes. Default is true.\n\
    --terminate-offline VALUE  Terminate if the target goes offline, otherwise the companion will stay alive.\n\
\n\
 Filter Options:\n\
    simulator                  Limit interactions to Simulators only.\n\
    device                     Limit interactions to Devices only.\n\
    ecid:ECID                  Limit interactions to a specific Device ECID\n\
";

static void WriteJSONToStdOut(id json)
{
  NSData *jsonOutput = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
  NSMutableData *readyOutput = [NSMutableData dataWithData:jsonOutput];
  [readyOutput appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
  write(STDOUT_FILENO, readyOutput.bytes, readyOutput.length);
  fflush(stdout);
}

static void WriteTargetToStdOut(id<FBiOSTargetInfo> target)
{
  WriteJSONToStdOut([[FBiOSTargetDescription alloc] initWithTarget:target].asJSON);
}

static FBFuture<FBSimulatorSet *> *SimulatorSetWithPath(NSString *deviceSetPath, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  // Give a more meaningful message if we can't load the frameworks.
  NSError *error = nil;
  if(![FBSimulatorControlFrameworkLoader.essentialFrameworks loadPrivateFrameworks:logger error:&error]) {
    return [FBFuture futureWithError:error];
  }
  FBSimulatorControlConfiguration *configuration = [FBSimulatorControlConfiguration configurationWithDeviceSetPath:deviceSetPath logger:logger reporter:reporter];
  FBSimulatorControl *control = [FBSimulatorControl withConfiguration:configuration error:&error];
  if (!control) {
    return [FBFuture futureWithError:error];
  }
  return [FBFuture futureWithResult:control.set];
}

static FBFuture<FBSimulatorSet *> *SimulatorSet(NSUserDefaults *userDefaults, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  NSString *deviceSetPath = [userDefaults stringForKey:@"-device-set-path"];
  return SimulatorSetWithPath(deviceSetPath, logger, reporter);
}

static FBFuture<FBDeviceSet *> *DeviceSet(id<FBControlCoreLogger> logger, NSString *ecidFilter)
{
  return [[FBFuture
    onQueue:dispatch_get_main_queue() resolveValue:^ FBDeviceSet * (NSError **error) {
      // Give a more meaningful message if we can't load the frameworks.
      if(![FBDeviceControlFrameworkLoader.new loadPrivateFrameworks:logger error:error]) {
        return nil;
      }
      FBDeviceSet *deviceSet = [FBDeviceSet setWithLogger:logger delegate:nil ecidFilter:ecidFilter error:error];
      if (!deviceSet) {
        return nil;
      }
      return deviceSet;
    }]
    delay:0.2]; // This is needed to give the Restorable Devices time to populate.
}

static FBFuture<NSArray<id<FBiOSTargetSet>> *> *DefaultTargetSets(NSUserDefaults *userDefaults, BOOL xcodeAvailable, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  NSString *only = [userDefaults stringForKey:@"-only"];
  if (only) {
    if ([only.lowercaseString containsString:@"simulator"]) {
      [logger log:@"'--only' set for Simulators"];
      return [FBFuture futureWithFutures:@[SimulatorSet(userDefaults, logger, reporter)]];
    }
    if ([only.lowercaseString containsString:@"device"]) {
      [logger log:@"'--only' set for Devices"];
      return [FBFuture futureWithFutures:@[DeviceSet(logger, nil)]];
    }
    if ([only.lowercaseString hasPrefix:@"ecid:"]) {
      NSString *ecid = [only.lowercaseString stringByReplacingOccurrencesOfString:@"ecid:" withString:@""];
      [logger logFormat:@"ECID filter of %@", ecid];
      return [FBFuture futureWithFutures:@[DeviceSet(logger, ecid)]];
    }
    return [[FBIDBError
      describeFormat:@"%@ is not a valid argument for '--only'", only]
      failFuture];
  }
  if (!xcodeAvailable) {
    [logger log:@"Xcode is not available, only Devices will be provided"];
    return [FBFuture futureWithFutures:@[DeviceSet(logger, nil)]];
  }
  [logger log:@"Providing targets across Simulator and Device sets."];
  return [FBFuture futureWithFutures:@[
    SimulatorSet(userDefaults, logger, reporter),
    DeviceSet(logger, nil),
  ]];
}

static FBFuture<id<FBiOSTarget>> *TargetForUDID(NSString *udid, NSUserDefaults *userDefaults, BOOL xcodeAvailable, BOOL warmUp, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  return [DefaultTargetSets(userDefaults, xcodeAvailable, logger, reporter)
    onQueue:dispatch_get_main_queue() fmap:^(NSArray<id<FBiOSTargetSet>> *targetSets) {
      return [FBiOSTargetProvider targetWithUDID:udid targetSets:targetSets warmUp:warmUp logger:logger];
    }];
}

static FBFuture<FBDevice *> *DeviceForECID(NSString *ecid, id<FBControlCoreLogger> logger)
{
  return [DeviceSet(logger, [ecid stringByReplacingOccurrencesOfString:@"ecid:" withString:@""])
    onQueue:dispatch_get_main_queue() fmap:^ FBFuture<NSNull *> * (FBDeviceSet *deviceSet) {
      NSArray<FBDevice *> *devices = deviceSet.allDevices;
      if (devices.count == 0) {
        return [[FBIDBError
          describeFormat:@"No devices %@ matching %@", [FBCollectionInformation oneLineDescriptionFromArray:devices], ecid]
          failFuture];
      }
      return [FBFuture futureWithResult:devices.firstObject];
    }];
}

static FBFuture<FBSimulator *> *SimulatorFuture(NSString *udid, NSUserDefaults *userDefaults, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  return [[SimulatorSet(userDefaults, logger, reporter)
    onQueue:dispatch_get_main_queue() fmap:^(FBSimulatorSet *simulatorSet) {
      return [FBiOSTargetProvider targetWithUDID:udid targetSets:@[simulatorSet] warmUp:NO logger:logger];
    }]
    onQueue:dispatch_get_main_queue() fmap:^(id<FBiOSTarget> target) {
      id<FBSimulatorLifecycleCommands> commands = (id<FBSimulatorLifecycleCommands>) target;
      if (![commands conformsToProtocol:@protocol(FBSimulatorLifecycleCommands)]) {
        return [[FBIDBError
          describeFormat:@"%@ does not support Simulator Lifecycle commands", commands]
          failFuture];
      }
      return [FBFuture futureWithResult:commands];
    }];
}

static FBFuture<NSNull *> *TargetOfflineFuture(id<FBiOSTarget> target, id<FBControlCoreLogger> logger)
{
  return [[target
    resolveLeavesState:FBiOSTargetStateBooted]
    onQueue:target.workQueue doOnResolved:^(id _){
      [target.logger log:@"Target is no longer booted, companion going offline"];
    }];
}

static FBFuture<FBFuture<NSNull *> *> *BootFuture(NSString *udid, NSUserDefaults *userDefaults, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  BOOL headless = [userDefaults boolForKey:@"-headless"];
  BOOL verifyBooted = [userDefaults objectForKey:@"-verify-booted"] == nil ? YES : [userDefaults boolForKey:@"-verify-booted"];
  return [[SimulatorFuture(udid, userDefaults, logger, reporter)
    onQueue:dispatch_get_main_queue() fmap:^(FBSimulator *simulator) {
      // Boot the simulator with the options provided.
      FBSimulatorBootOptions options = FBSimulatorBootConfiguration.defaultConfiguration.options;
      if (headless) {
        [logger logFormat:@"Booting %@ headlessly", udid];
        options = options | FBSimulatorBootOptionsTieToProcessLifecycle;
      } else {
        [logger logFormat:@"Booting %@ normally", udid];
        options = options & ~FBSimulatorBootOptionsTieToProcessLifecycle;
      }
      if (verifyBooted) {
        [logger logFormat:@"Booting %@ with verification", udid];
        options = options | FBSimulatorBootOptionsVerifyUsable;
      } else {
        [logger logFormat:@"Booting %@ without verification", udid];
        options = options & ~FBSimulatorBootOptionsVerifyUsable;
      }
      FBSimulatorBootConfiguration *config = [[FBSimulatorBootConfiguration alloc] initWithOptions:options environment:@{}];
      return [[simulator boot:config] mapReplace:simulator];
    }]
    onQueue:dispatch_get_main_queue() map:^ FBFuture<NSNull *> * (FBSimulator *simulator) {
      // Write the boot success to stdout
      WriteTargetToStdOut(simulator);
      // In a headless boot:
      // - We need to keep this process running until it's otherwise shutdown. When the sim is shutdown this process will die.
      // - If this process is manually killed then the simulator will die
      // For a regular boot the sim will outlive this process.
      if (!headless) {
        return FBFuture.empty;
      }
      // Whilst we can rely on this process being killed shutting the simulator, this is asynchronous.
      // This means that we should attempt to handle cancellation gracefully.
      // In this case we should attempt to shutdown in response to cancellation.
      // This means if this future is cancelled and waited-for before the process exits we will return it in a "Shutdown" state.
      return [TargetOfflineFuture(simulator, logger)
        onQueue:dispatch_get_main_queue() respondToCancellation:^{
          return [simulator shutdown];
        }];
    }];
}

static FBFuture<NSNull *> *ShutdownFuture(NSString *udid, NSUserDefaults *userDefaults, BOOL xcodeAvailable, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  return [TargetForUDID(udid, userDefaults, xcodeAvailable, NO, logger, reporter)
    onQueue:dispatch_get_main_queue() fmap:^ FBFuture<NSNull *> * (id<FBiOSTarget> target) {
      id<FBPowerCommands> commands = (id<FBPowerCommands>) target;
      if (![commands conformsToProtocol:@protocol(FBPowerCommands)]) {
        return [[FBIDBError
          describeFormat:@"Cannot shutdown %@, does not support shutting down", target]
          failFuture];
      }
      return [commands shutdown];
    }];
}

static FBFuture<NSNull *> *RebootFuture(NSString *udid, NSUserDefaults *userDefaults, BOOL xcodeAvailable, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  return [TargetForUDID(udid, userDefaults, xcodeAvailable, NO, logger, reporter)
    onQueue:dispatch_get_main_queue() fmap:^ FBFuture<NSNull *> * (id<FBiOSTarget> target) {
      id<FBPowerCommands> commands = (id<FBPowerCommands>) target;
      if (![commands conformsToProtocol:@protocol(FBPowerCommands)]) {
        return [[FBIDBError
          describeFormat:@"Cannot shutdown %@, does not support rebooting", target]
          failFuture];
      }
      return [commands reboot];
    }];
}

static FBFuture<NSNull *> *EraseFuture(NSString *udid, NSUserDefaults *userDefaults, BOOL xcodeAvailable, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  return [TargetForUDID(udid, userDefaults, xcodeAvailable, NO, logger, reporter)
    onQueue:dispatch_get_main_queue() fmap:^ FBFuture<NSNull *> * (id<FBiOSTarget> target) {
      id<FBEraseCommands> commands = (id<FBEraseCommands>) target;
      if (![commands conformsToProtocol:@protocol(FBEraseCommands)]) {
        return [[FBIDBError
          describeFormat:@"Cannot erase %@, does not support erasing", target]
          failFuture];
      }
      return [commands erase];
    }];
}

static FBFuture<NSNull *> *DeleteFuture(NSString *udidOrAll, NSUserDefaults *userDefaults, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  return [[SimulatorSet(userDefaults, logger, reporter)
    onQueue:dispatch_get_main_queue() fmap:^ FBFuture * (FBSimulatorSet *set) {
      if ([udidOrAll.lowercaseString isEqualToString:@"all"]) {
        return [set deleteAll];
      }
      FBSimulator *simulator = [set simulatorWithUDID:udidOrAll];
      if (!simulator) {
        return [[FBIDBError
          describeFormat:@"Could not find a simulator with udid %@", udidOrAll]
          failFuture];
      }
      return [set delete:simulator];
    }]
    mapReplace:NSNull.null];
}

static FBFuture<NSNull *> *ListFuture(NSUserDefaults *userDefaults, BOOL xcodeAvailable, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  return [DefaultTargetSets(userDefaults, xcodeAvailable, logger, reporter)
    onQueue:dispatch_get_main_queue() map:^ NSNull * (NSArray<id<FBiOSTargetSet>> *targetSets) {
      NSUInteger reportedCount = 0;
      for (id<FBiOSTargetSet> targetSet in targetSets) {
        for (id<FBiOSTargetInfo> targetInfo in targetSet.allTargetInfos) {
          WriteTargetToStdOut(targetInfo);
          reportedCount++;
        }
      }
      [logger logFormat:@"Reported %lu targets to stdout", reportedCount];
      return NSNull.null;
    }];
}

static FBFuture<NSNull *> *CreateFuture(NSString *create, NSUserDefaults *userDefaults, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  return [[SimulatorSet(userDefaults, logger, reporter)
    onQueue:dispatch_get_main_queue() fmap:^ FBFuture<FBSimulator *> * (FBSimulatorSet *set) {
      NSArray<NSString *> *parameters = [create componentsSeparatedByString:@","];
      FBSimulatorConfiguration *config = [FBSimulatorConfiguration defaultConfiguration];
      if (parameters.count > 0) {
        config = [config withDeviceModel:parameters[0]];
      }
      if (parameters.count > 1) {
        config = [config withOSNamed:parameters[1]];
      }
      return [set createSimulatorWithConfiguration:config];
    }]
    onQueue:dispatch_get_main_queue() map:^(FBSimulator *simulator) {
      WriteTargetToStdOut(simulator);
      return NSNull.null;
    }];
}

static FBFuture<NSNull *> *CloneFuture(NSString *udid, NSUserDefaults *userDefaults, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  NSString *destinationSet = [userDefaults stringForKey:@"-clone-destination-set"];
  return [[[FBFuture
    futureWithFutures:@[
      SimulatorFuture(udid, userDefaults, logger, reporter),
      SimulatorSetWithPath(destinationSet, logger, reporter),
    ]]
    onQueue:dispatch_get_main_queue() fmap:^ FBFuture<FBSimulator *> * (NSArray<id> *tuple) {
      FBSimulator *base = tuple[0];
      FBSimulatorSet *destination = tuple[1];
      return [base.set cloneSimulator:base toDeviceSet:destination];
    }]
    onQueue:dispatch_get_main_queue() map:^(FBSimulator *cloned) {
      WriteTargetToStdOut(cloned);
      return NSNull.null;
    }];
}

static FBFuture<NSNull *> *EnterRecoveryFuture(NSString *ecid, id<FBControlCoreLogger> logger)
{
  return [DeviceForECID(ecid, logger)
    onQueue:dispatch_get_main_queue() fmap:^ FBFuture<NSNull *> * (FBDevice *device) {
      return [device enterRecovery];
    }];
}
static FBFuture<NSNull *> *ExitRecoveryFuture(NSString *ecid, id<FBControlCoreLogger> logger)
{
  return [DeviceForECID(ecid, logger)
    onQueue:dispatch_get_main_queue() fmap:^ FBFuture<NSNull *> * (FBDevice *device) {
      return [device exitRecovery];
    }];
}

static FBFuture<NSNull *> *ActivateFuture(NSString *ecid, id<FBControlCoreLogger> logger)
{
  return [DeviceForECID(ecid, logger)
    onQueue:dispatch_get_main_queue() fmap:^ FBFuture<NSNull *> * (FBDevice *device) {
      return [device activate];
    }];
}

static FBFuture<NSNull *> *CleanFuture(NSString *udid, NSUserDefaults *userDefaults, BOOL xcodeAvailable, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  return [TargetForUDID(udid, userDefaults, xcodeAvailable, YES, logger, reporter)
          onQueue:dispatch_get_main_queue() fmap:^FBFuture<NSNull *> *(id<FBiOSTarget> target) {
    NSError *error = nil;
    FBIDBStorageManager *storageManager = [FBIDBStorageManager managerForTarget:target logger:logger error:&error];
    if (!storageManager) {
      return [FBFuture futureWithError:error];
    }
    FBIDBCommandExecutor *commandExecutor = [FBIDBCommandExecutor
                                             commandExecutorForTarget:target
                                             storageManager:storageManager
                                             temporaryDirectory:[FBTemporaryDirectory temporaryDirectoryWithLogger:logger]
                                             debugserverPort:[[IDBPortsConfiguration alloc] initWithArguments:userDefaults].debugserverPort
                                             logger:logger];
    return [commandExecutor clean];
  }];
}

static FBFuture<FBFuture<NSNull *> *> *CompanionServerFuture(NSString *udid, NSUserDefaults *userDefaults, BOOL xcodeAvailable, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  BOOL terminateOffline = [userDefaults boolForKey:@"-terminate-offline"];

  return [TargetForUDID(udid, userDefaults, xcodeAvailable, YES, logger, reporter)
    onQueue:dispatch_get_main_queue() fmap:^(id<FBiOSTarget> target) {
      [reporter addMetadata:@{
        @"udid": udid,
        @"target_type": FBiOSTargetTypeStringFromTargetType(target.targetType).lowercaseString,
      }];
      [reporter report:[FBEventReporterSubject subjectForEvent:@"launched"]];

      FBTemporaryDirectory *temporaryDirectory = [FBTemporaryDirectory temporaryDirectoryWithLogger:logger];
      NSError *error = nil;

      FBIDBStorageManager *storageManager = [FBIDBStorageManager managerForTarget:target logger:logger error:&error];
      if (!storageManager) {
        return [FBFuture futureWithError:error];
      }
      NSError *err = nil;

      // Start up the companion
      IDBPortsConfiguration *ports = [[IDBPortsConfiguration alloc] initWithArguments:userDefaults];

      // Command Executor
      FBIDBCommandExecutor *commandExecutor = [FBIDBCommandExecutor
                                               commandExecutorForTarget:target
                                               storageManager:storageManager
                                               temporaryDirectory:temporaryDirectory
                                               debugserverPort:ports.debugserverPort
                                               logger:logger];

      FBIDBCommandExecutor *loggingCommandExecutor = [FBLoggingWrapper wrap:commandExecutor simplifiedNaming:YES eventReporter:IDBConfiguration.swiftEventReporter logger:logger];

      GRPCSwiftServer *swiftServer = [[GRPCSwiftServer alloc]
                                      initWithTarget:target
                                      commandExecutor:loggingCommandExecutor
                                      reporter:IDBConfiguration.swiftEventReporter
                                      logger:logger
                                      ports:ports
                                      error:&err];
      if (!swiftServer) {
        return [FBFuture futureWithError:err];
      }

      return [[swiftServer start] onQueue:target.workQueue map:^ FBFuture * (NSDictionary<NSString *, id> *serverDescription) {
        WriteJSONToStdOut(serverDescription);
        NSMutableArray<FBFuture<NSNull *> *> *futures = [[NSMutableArray alloc] initWithArray: @[swiftServer.completed]];

        if (terminateOffline) {
          [logger.info logFormat:@"Companion will terminate when target goes offline"];
          [futures addObject:TargetOfflineFuture(target, logger)];
        } else {
          [logger.info logFormat:@"Companion will stay alive if target goes offline"];
        }

        FBFuture<NSNull *> *completed = [FBFuture race: futures];
        return [completed
                onQueue:target.workQueue chain:^(FBFuture *future) {
          [temporaryDirectory cleanOnExit];
          return future;
        }];
      }];
  }];
}

static FBFuture<FBFuture<NSNull *> *> *NotiferFuture(NSString *notify, NSUserDefaults *userDefaults, BOOL xcodeAvailable, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  return [[[DefaultTargetSets(userDefaults, xcodeAvailable, logger, reporter)
    onQueue:dispatch_get_main_queue() fmap:^(NSArray<id<FBiOSTargetSet>> *targetSets) {
      if ([notify isEqualToString:@"stdout"]) {
        return [FBiOSTargetStateChangeNotifier notifierToStdOutWithTargetSets:targetSets logger:logger];
      }
      return [FBiOSTargetStateChangeNotifier notifierToFilePath:notify withTargetSets:targetSets logger:logger];
    }]
    onQueue:dispatch_get_main_queue() fmap:^(FBiOSTargetStateChangeNotifier *notifier) {
      [logger logFormat:@"Starting Notifier %@", notifier];
      return [[notifier startNotifier] mapReplace:notifier];
    }]
    onQueue:dispatch_get_main_queue() map:^(FBiOSTargetStateChangeNotifier *notifier) {
      [logger logFormat:@"Started Notifier %@", notifier];
      return [notifier.notifierDone
        onQueue:dispatch_get_main_queue() respondToCancellation:^{
          [logger logFormat:@"Stopping Notifier %@", notifier];
          return FBFuture.empty;
        }];
    }];
}

static FBFuture<NSNull *> *ForwardFuture(NSString *forward, NSUserDefaults *userDefaults, BOOL xcodeAvailable, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  NSArray<NSString *> *components = [forward componentsSeparatedByString:@":"];
  if (components.count != 2) {
    return [[FBIDBError
      describeFormat:@"%@ should be of the form UDID:PORT", forward]
      failFuture];
  }
  NSString *udid = components[0];
  int remotePort = [components[1] intValue];

  return [TargetForUDID(udid, userDefaults, xcodeAvailable, NO, logger, reporter)
    onQueue:dispatch_get_main_queue() fmap:^ FBFuture<NSNull *> * (id<FBiOSTarget> target) {
      id<FBSocketForwardingCommands> commands = (id<FBSocketForwardingCommands>) target;
      if (![commands conformsToProtocol:@protocol(FBSocketForwardingCommands)]) {
        return [[FBIDBError
          describeFormat:@"%@ does not conform to FBSocketForwardingCommands", target]
          failFuture];
      }
      return [commands drainLocalFileInput:STDIN_FILENO localFileOutput:STDOUT_FILENO remotePort:remotePort];
    }];
}

static FBFuture<FBFuture<NSNull *> *> *GetCompanionCompletedFuture(NSUserDefaults *userDefaults, BOOL xcodeAvailable, id<FBControlCoreLogger> logger) {
  NSString *boot = [userDefaults stringForKey:@"-boot"];
  NSString *reboot = [userDefaults stringForKey:@"-reboot"];
  NSString *clone = [userDefaults stringForKey:@"-clone"];
  NSString *create = [userDefaults stringForKey:@"-create"];
  NSString *delete = [userDefaults stringForKey:@"-delete"];
  NSString *erase = [userDefaults stringForKey:@"-erase"];
  NSString *list = [userDefaults stringForKey:@"-list"];
  NSString *notify = [userDefaults stringForKey:@"-notify"];
  NSString *recover = [userDefaults stringForKey:@"-recover"];
  NSString *shutdown = [userDefaults stringForKey:@"-shutdown"];
  NSString *udid = [userDefaults stringForKey:@"-udid"];
  NSString *unrecover = [userDefaults stringForKey:@"-unrecover"];
  NSString *activate = [userDefaults stringForKey:@"-activate"];
  NSString *clean = [userDefaults stringForKey:@"-clean"];
  NSString *forward = [userDefaults stringForKey:@"-forward"];

  id<FBEventReporter> reporter = IDBConfiguration.eventReporter;
  if (udid) {
    return CompanionServerFuture(udid, userDefaults, xcodeAvailable, logger, reporter);
  } else if (list) {
    [logger.info log:@"Listing"];
    return [FBFuture futureWithResult:ListFuture(userDefaults, xcodeAvailable, logger, reporter)];
  } else if (notify) {
    [logger.info logFormat:@"Notifying %@", notify];
    return NotiferFuture(notify, userDefaults, xcodeAvailable, logger, reporter);
  } else if (boot) {
    [logger logFormat:@"Booting %@", boot];
    return BootFuture(boot, userDefaults, logger, reporter);
  } else if (shutdown) {
    [logger.info logFormat:@"Shutting down %@", shutdown];
    return [FBFuture futureWithResult:ShutdownFuture(shutdown, userDefaults, xcodeAvailable, logger, reporter)];
  } else if (reboot) {
    [logger.info logFormat:@"Rebooting %@", reboot];
    return [FBFuture futureWithResult:RebootFuture(reboot, userDefaults, xcodeAvailable, logger, reporter)];
  } else if (erase) {
    [logger.info logFormat:@"Erasing %@", erase];
    return [FBFuture futureWithResult:EraseFuture(erase, userDefaults, xcodeAvailable, logger, reporter)];
  } else if (delete) {
    [logger.info logFormat:@"Deleting %@", delete];
    return [FBFuture futureWithResult:DeleteFuture(delete, userDefaults, logger, reporter)];
  } else if (create) {
    [logger.info logFormat:@"Creating %@", create];
    return [FBFuture futureWithResult:CreateFuture(create, userDefaults, logger, reporter)];
  } else if (clone) {
    [logger.info logFormat:@"Cloning %@", clone];
    return [FBFuture futureWithResult:CloneFuture(clone, userDefaults, logger, reporter)];
  } else if (recover) {
    [logger.info logFormat:@"Putting %@ into recovery", recover];
    return [FBFuture futureWithResult:EnterRecoveryFuture(recover, logger)];
  } else if (unrecover) {
    [logger.info logFormat:@"Removing %@ from recovery", recover];
    return [FBFuture futureWithResult:ExitRecoveryFuture(unrecover, logger)];
  } else if (activate) {
    [logger.info logFormat:@"Activating %@", activate];
    return [FBFuture futureWithResult:ActivateFuture(activate, logger)];
  } else if (clean) {
    [logger.info logFormat:@"Cleaning %@", clean];
    return [FBFuture futureWithResult:CleanFuture(clean, userDefaults, xcodeAvailable, logger, reporter)];
  } else if (forward) {
    [logger.info logFormat:@"Forwarding %@", forward];
    return [FBFuture futureWithResult:ForwardFuture(forward, userDefaults, xcodeAvailable, logger, reporter)];
  }
  return [[FBIDBError
    describeFormat:@"You must specify at least one 'Mode of operation'\n\n%s", kUsageHelpMessage]
    failFuture];
}

static FBFuture<NSNumber *> *signalHandlerFuture(uintptr_t signalCode, NSString *exitMessage, id<FBControlCoreLogger> logger)
{
  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
  FBMutableFuture<NSNumber *> *future = FBMutableFuture.future;
  dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, signalCode, 0, dispatch_get_main_queue());
  dispatch_source_set_event_handler(source, ^{
    [logger.error log:exitMessage];
    [future resolveWithResult:@(signalCode)];
  });
  dispatch_resume(source);
  struct sigaction action = {{0}};
  action.sa_handler = SIG_IGN;
  sigaction((int)signalCode, &action, NULL);
  return [future
    onQueue:queue notifyOfCompletion:^(FBFuture *_) {
      dispatch_cancel(source);
    }];
}

static NSString *EnvDescription(void)
{
  return [FBCollectionInformation oneLineDescriptionFromDictionary:FBControlCoreGlobalConfiguration.safeSubprocessEnvironment];
}

static NSString *ArchName(void)
{
#if TARGET_CPU_ARM64
  return @"arm64";
#elif TARGET_CPU_X86_64
  return @"x86_64";
#else
  return @"not supported");
#endif
}

static void logStartupInfo(FBIDBLogger *logger)
{
    [logger.info logFormat:@"IDB Companion Built at %s %s", __DATE__, __TIME__];
    [logger.info logFormat:@"IDB Companion architecture %@", ArchName()];
    [logger.info logFormat:@"Invoked with args=%@ env=%@", [FBCollectionInformation oneLineDescriptionFromArray:NSProcessInfo.processInfo.arguments], EnvDescription()];
}

int main(int argc, const char *argv[]) {
  @autoreleasepool
  {
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    if ([arguments containsObject:@"--help"]) {
      fprintf(stderr, "%s", kUsageHelpMessage);
      return 1;
    }
    if ([arguments containsObject:@"--version"]) {
      WriteJSONToStdOut(@{@"build_time": @(__TIME__), @"build_date": @(__DATE__)});
      return 0;
    }

    NSUserDefaults *userDefaults = NSUserDefaults.standardUserDefaults;
    FBIDBLogger *logger = [FBIDBLogger loggerWithUserDefaults:userDefaults];
    logStartupInfo(logger);

    NSError *error = nil;

    // Check that xcode-select returns a valid path, throw a big
    // warning if not
    BOOL xcodeAvailable = [FBXcodeDirectory.xcodeSelectDeveloperDirectory await:&error] != nil;
    if (!xcodeAvailable) {
      [logger.error logFormat:@"Xcode is not available, idb will not be able to use Simulators: %@", error];
      error = nil;
    }

    FBFuture<NSNumber *> *signalled = [FBFuture race:@[
      signalHandlerFuture(SIGINT, @"Signalled: SIGINT", logger),
      signalHandlerFuture(SIGTERM, @"Signalled: SIGTERM", logger),
    ]];
    FBFuture<NSNull *> *companionCompleted = [GetCompanionCompletedFuture(userDefaults, xcodeAvailable, logger) await:&error];
    if (!companionCompleted) {
      [logger.error log:error.localizedDescription];
      return 1;
    }

    FBFuture<NSNull *> *completed = [FBFuture race:@[
      companionCompleted,
      signalled,
    ]];
    if (completed.error) {
      [logger.error log:completed.error.localizedDescription];
      return 1;
    }
    id result = [completed await:&error];
    if (!result) {
      [logger.error log:error.localizedDescription];
      return 1;
    }
    if (companionCompleted.state == FBFutureStateCancelled) {
      [logger logFormat:@"Responding to termination of idb with signo %@", result];
      FBFuture<NSNull *> *cancellation = [companionCompleted cancel];
      result = [cancellation await:&error];
      if (!result) {
        [logger.error log:error.localizedDescription];
        return 1;
      }
    }
  }
  return 0;
}
