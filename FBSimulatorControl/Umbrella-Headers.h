//
//  Umbrella-Headers.h
//  FBSimulatorControl
//
//  Created by Geoffrey Blotter on 11/19/15.
//
//

#ifndef Umbrella_Headers_h
#define Umbrella_Headers_h

// Logs
#import "FBSimulatorLogs.h"
#import "FBSimulatorLogs+Private.h"
#import "FBWritableLog.h"
#import "FBWritableLog+Private.h"


// Configuration
#import "FBProcessLaunchConfiguration+Helpers.h"
#import "FBProcessLaunchConfiguration+Private.h"
#import "FBProcessLaunchConfiguration.h"
#import "FBSimulatorConfiguration+Convenience.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorConfiguration+Private.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorControlStaticConfiguration.h"


// Management
#import "FBSimulator.h"
#import "FBSimulator+Private.h"
#import "FBSimulator+Queries.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControl+Private.h"
#import "FBSimulatorInteraction.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorPool+Private.h"
#import "FBSimulatorPredicates.h"


// Model
#import "FBSimulatorApplication.h"
#import "FBSimulatorProcess+Private.h"
#import "FBSimulatorProcess.h"


// Notifications
#import "FBCoreSimulatorNotifier.h"
#import "FBDispatchSourceNotifier.h"


// Session
#import "FBSimulatorSession+Convenience.h"
#import "FBSimulatorSession+Private.h"
#import "FBSimulatorSession.h"
#import "FBSimulatorSessionInteraction+Diagnostics.h"
#import "FBSimulatorSessionInteraction+Private.h"
#import "FBSimulatorSessionInteraction.h"
#import "FBSimulatorSessionLifecycle.h"
#import "FBSimulatorSessionState+Private.h"
#import "FBSimulatorSessionState+Queries.h"
#import "FBSimulatorSessionState.h"
#import "FBSimulatorSessionStateGenerator.h"


// Tasks
#import "FBTask+Private.h"
#import "FBTask.h"
#import "FBTaskExecutor+Convenience.h"
#import "FBTaskExecutor+Private.h"
#import "FBTaskExecutor.h"
#import "FBTerminationHandle.h"


// Tiling
#import "FBSimulatorWindowHelpers.h"
#import "FBSimulatorWindowTiler.h"
#import "FBSimulatorWindowTilingStrategy.h"


// Utility
#import "FBConcurrentCollectionOperations.h"
#import "FBInteraction.h"
#import "FBInteraction+Private.h"
#import "FBSimulatorError.h"
#import "FBSimulatorLogger.h"
#import "NSRunLoop+SimulatorControlAdditions.h"


// Video
#import "FBSimulatorVideoUploader.h"
#import "FBSimulatorVideoRecorder.h"


#endif /* Umbrella_Headers_h */
