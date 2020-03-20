/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBIDBCompanionServer.h"
#import "FBIDBConfiguration.h"
#import "FBIDBError.h"
#import "FBIDBLogger.h"
#import "FBIDBPortsConfiguration.h"
#import "FBiOSTargetProvider.h"
#import "FBiOSTargetStateChangeNotifier.h"
#import "FBStorageUtils.h"
#import "FBTemporaryDirectory.h"

const char *kUsageHelpMessage = "\
Usage: \n \
  Modes of operation, only one of these may be specified:\n\
    --udid UDID                Launches a companion server for the specified UDID.\n\
    --boot UDID                Boots the simulator with the specified UDID.\n\
    --shutdown UDID            Shuts down the simulator with the specified UDID.\n\
    --erase UDID               Erases the simulator with the specified UDID.\n\
    --delete UDID|all          Deletes the simulator with the specified UDID, or 'all' to delete all simulators in the set. \n\
    --create VALUE             Creates a simulator using the VALUE argument like \"iPhone X, iOS 12.4\"\n\
    --notify PATH              Launches a companionn notifier which will stream availability updates to the specified path.\n\
    --help                     Show this help message and exit.\n\
\n\
  Options:\n\
    --grpc-port PORT           Port to start the grpc companion server on (default: 10882).\n\
    --debug-port PORT          Port to connect debugger on (default: 10881).\n\
    --log-file-path PATH       Path to write a log file to e.g ./output.log (default: logs to stdErr).\n\
    --device-set-path PATH     Path to a custom Simulator device set.\n\
    --terminate-offline VALUE  Terminate if the target goes offline, otherwise the companion will stay alive.\n";

static BOOL shouldPrintUsage(void) {
  return [NSProcessInfo.processInfo.arguments containsObject:@"--help"];
}

static FBFuture<FBSimulatorSet *> *SimulatorSet(NSUserDefaults *userDefaults, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  NSString *deviceSetPath = [userDefaults stringForKey:@"-device-set-path"];
  FBSimulatorControlConfiguration *configuration = [FBSimulatorControlConfiguration configurationWithDeviceSetPath:deviceSetPath options:0 logger:logger reporter:reporter];
  NSError *error = nil;
  FBSimulatorControl *control = [FBSimulatorControl withConfiguration:configuration error:&error];
  if (!control) {
    return [FBFuture futureWithError:error];
  }
  return [FBFuture futureWithResult:control.set];
}

static FBFuture<id<FBSimulatorLifecycleCommands>> *LifecycleCommandsFuture(NSString *udid, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  NSError *error = nil;
  id<FBiOSTarget> target = [FBiOSTargetProvider targetWithUDID:udid logger:logger reporter:reporter error:&error];
  if (!target) {
    return [FBFuture futureWithError:error];
  }
  id<FBSimulatorLifecycleCommands> commands = (id<FBSimulatorLifecycleCommands>) target;
  if (![commands conformsToProtocol:@protocol(FBSimulatorLifecycleCommands)]) {
    return [[FBIDBError
      describeFormat:@"%@ does not support Simulator Lifecycle commands", commands]
      failFuture];
  }
  return [FBFuture futureWithResult:commands];
}

static FBFuture<NSNull *> *TargetOfflineFuture(id<FBiOSTarget> target, id<FBControlCoreLogger> logger)
{
  return [[FBFuture
    onQueue:target.workQueue resolveWhen:^ BOOL {
      if (target.state != FBiOSTargetStateBooted) {
        [logger.error logFormat:@"Target with udid %@ is no longer booted, it is in state %@", target.udid, FBiOSTargetStateStringFromState(target.state)];
        return YES;
      }
      return NO;
    }]
    mapReplace:NSNull.null];
}

static FBFuture<NSNull *> *BootFuture(NSString *udid, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  return [LifecycleCommandsFuture(udid, logger, reporter)
    onQueue:dispatch_get_main_queue() fmap:^(id<FBSimulatorLifecycleCommands> commands) {
      return [commands boot];
    }];
}

static FBFuture<NSNull *> *ShutdownFuture(NSString *udid, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  return [LifecycleCommandsFuture(udid, logger, reporter)
    onQueue:dispatch_get_main_queue() fmap:^(id<FBSimulatorLifecycleCommands> commands) {
      return [commands shutdown];
    }];
}

static FBFuture<NSNull *> *EraseFuture(NSString *udid, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  return [LifecycleCommandsFuture(udid, logger, reporter)
    onQueue:dispatch_get_main_queue() fmap:^(id<FBSimulatorLifecycleCommands> commands) {
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
      NSArray<FBSimulator *> *simulators = [set query:[FBiOSTargetQuery udid:udidOrAll]];
      if (simulators.count != 1) {
        return [[FBIDBError
          describeFormat:@"Could not find a simulator with udid %@ got %@", udidOrAll, [FBCollectionInformation oneLineDescriptionFromArray:simulators]]
          failFuture];
      }
      return [set deleteSimulator:simulators.firstObject];
    }]
    mapReplace:NSNull.null];
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
    mapReplace:NSNull.null];
}

static FBFuture<FBFuture<NSNull *> *> *CompanionServerFuture(NSString *udid, NSUserDefaults *userDefaults, id<FBControlCoreLogger> logger, id<FBEventReporter> reporter)
{
  BOOL terminateOffline = [userDefaults boolForKey:@"-terminate-offline"];
  NSError *error = nil;
  if ([udid isEqualToString:@"mac"]) {
    udid = [FBMacDevice resolveDeviceUDID];
  }
  id<FBiOSTarget> target = [FBiOSTargetProvider targetWithUDID:udid logger:logger reporter:reporter error:&error];
  if (!target) {
    return [FBFuture futureWithError:error];
  }
  [reporter addMetadata:@{@"udid": udid}];
  [reporter report:[FBEventReporterSubject subjectForEvent:FBEventNameLaunched]];
  // Start up the companion
  FBIDBPortsConfiguration *ports = [FBIDBPortsConfiguration portsWithArguments:userDefaults];
  FBTemporaryDirectory *temporaryDirectory = [FBTemporaryDirectory temporaryDirectoryWithLogger:logger];
  FBIDBCompanionServer *server = [FBIDBCompanionServer companionForTarget:target temporaryDirectory:temporaryDirectory ports:ports eventReporter:reporter logger:logger error:&error];
  if (!server) {
    return [FBFuture futureWithError:error];
  }

  return [[server
    start]
    onQueue:target.workQueue map:^id(NSNumber *port) {
      NSData *jsonOutput = [NSJSONSerialization dataWithJSONObject:@{@"grpc_port": port} options:0 error:nil];
      NSMutableData *readyOutput = [NSMutableData dataWithData:jsonOutput];
      [readyOutput appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
      write(STDOUT_FILENO, readyOutput.bytes, readyOutput.length);
      fflush(stdout);
      FBFuture<NSNull *> *completed = server.completed;
      if (terminateOffline) {
        [logger.info logFormat:@"Companion will terminate when target goes offline"];
        completed = [FBFuture race:@[completed, TargetOfflineFuture(target, logger)]];
      } else {
        [logger.info logFormat:@"Companion will stay alive if target goes offline"];
      }
      return [completed
        onQueue:target.workQueue chain:^(FBFuture *future) {
          [temporaryDirectory cleanOnExit];
          return future;
        }];
    }];

}

static FBFuture<FBFuture<NSNull *> *> *GetCompanionCompletedFuture(int argc, const char *argv[], NSUserDefaults *userDefaults, FBIDBLogger *logger) {
  NSString *udid = [userDefaults stringForKey:@"-udid"];
  NSString *notifyFilePath = [userDefaults stringForKey:@"-notify"];
  NSString *boot = [userDefaults stringForKey:@"-boot"];
  NSString *create = [userDefaults stringForKey:@"-create"];
  NSString *shutdown = [userDefaults stringForKey:@"-shutdown"];
  NSString *erase = [userDefaults stringForKey:@"-erase"];
  NSString *delete = [userDefaults stringForKey:@"-delete"];

  id<FBEventReporter> reporter = FBIDBConfiguration.eventReporter;
  if (udid) {
    return CompanionServerFuture(udid, userDefaults, logger, reporter);
  } else if (notifyFilePath) {
    [logger.info logFormat:@"Notify mode is set. writing updates to %@", notifyFilePath];
    return [[FBiOSTargetStateChangeNotifier notifierToFilePath:notifyFilePath logger:logger] startNotifier];
  } else if (boot) {
    [logger.info log:@"Booting target"];
    return [FBFuture futureWithResult:BootFuture(boot, logger, reporter)];
  } else if(shutdown) {
    [logger.info logFormat:@"Shutting down %@", shutdown];
    return [FBFuture futureWithResult:ShutdownFuture(shutdown, logger, reporter)];
  } else if (erase) {
    [logger.info logFormat:@"Erasing %@", erase];
    return [FBFuture futureWithResult:EraseFuture(erase, logger, reporter)];
  } else if (delete) {
    [logger.info logFormat:@"Deleting %@", delete];
    return [FBFuture futureWithResult:DeleteFuture(delete, userDefaults, logger, reporter)];
  } else if (create) {
    [logger.info logFormat:@"Creating %@", create];
    return [FBFuture futureWithResult:CreateFuture(create, userDefaults, logger, reporter)];
  }
  return [[[FBIDBError
    describeFormat:@"You must specify at least one 'Mode of operation'\n\n%s", kUsageHelpMessage]
    noLogging]
    failFuture];
}

static FBFuture<NSNumber *> *signalHandlerFuture(int signalCode, NSString *exitMessage, id<FBControlCoreLogger> logger)
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
  sigaction(signalCode, &action, NULL);
  return [future
    onQueue:queue notifyOfCompletion:^(FBFuture *_) {
      dispatch_cancel(source);
    }];
}

int main(int argc, const char *argv[]) {
  if (shouldPrintUsage()) {
    fprintf(stderr, "%s", kUsageHelpMessage);
    return 1;
  }

  @autoreleasepool {
    NSUserDefaults *userDefaults = NSUserDefaults.standardUserDefaults;
    FBIDBLogger *logger = [FBIDBLogger loggerWithUserDefaults:userDefaults];
    [logger.info logFormat:@"IDB Companion Built at %s %s", __DATE__, __TIME__];
    [logger.info logFormat:@"Invoked with args=%@ env=%@", [FBCollectionInformation oneLineDescriptionFromArray:NSProcessInfo.processInfo.arguments], [FBCollectionInformation oneLineDescriptionFromDictionary:NSProcessInfo.processInfo.environment]];

    NSError *error = nil;
    FBFuture<NSNull *> *completed = [GetCompanionCompletedFuture(argc, argv, userDefaults, logger) await:&error];
    if (!completed) {
      [logger.error log:error.localizedDescription];
      return 1;
    }

    completed = [FBFuture race:@[
      completed,
      signalHandlerFuture(SIGINT, @"Exiting: SIGINT", logger),
      signalHandlerFuture(SIGTERM, @"Exiting: SIGTERM", logger),
    ]];
    if (completed.error) {
      [logger.error log:completed.error.localizedDescription];
      return 1;
    }
    [completed await:nil];
  }
  return 0;
}
