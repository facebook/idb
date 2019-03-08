/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@class NSArray, NSDictionary, NSNumber, NSString, NSUUID, DTXRemoteInvocationReceipt;

@protocol XCTestManager_DaemonConnectionInterface
- (DTXRemoteInvocationReceipt *)_IDE_stopRecording;
- (DTXRemoteInvocationReceipt *)_IDE_startRecordingProcessPID:(NSNumber *)arg1 applicationSnapshotAttributes:(NSArray *)arg2 applicationSnapshotParameters:(NSDictionary *)arg3 elementSnapshotAttributes:(NSArray *)arg4 elementSnapshotParameters:(NSDictionary *)arg5 simpleTargetGestureNames:(NSArray *)arg6;
- (DTXRemoteInvocationReceipt *)_IDE_startRecordingProcessPID:(NSNumber *)arg1 snapshotAttributes:(NSArray *)arg2 snapshotParameters:(NSDictionary *)arg3 simpleTargetGestureNames:(NSArray *)arg4;
- (DTXRemoteInvocationReceipt *)_IDE_startRecordingProcessPID:(NSNumber *)arg1;
- (DTXRemoteInvocationReceipt *)_IDE_startRecording;
- (DTXRemoteInvocationReceipt *)_IDE_beginSessionWithIdentifier:(NSUUID *)arg1 forClient:(NSString *)arg2 atPath:(NSString *)arg3;
- (DTXRemoteInvocationReceipt *)_IDE_initiateControlSessionForTestProcessID:(NSNumber *)arg1;
- (DTXRemoteInvocationReceipt *)_IDE_initiateControlSessionForTestProcessID:(NSNumber *)arg1 protocolVersion:(NSNumber *)arg2;
- (DTXRemoteInvocationReceipt *)_IDE_initiateSessionWithIdentifier:(NSUUID *)arg1 forClient:(NSString *)arg2 atPath:(NSString *)arg3 protocolVersion:(NSNumber *)arg4;

// iOS 10.x specific
- (DTXRemoteInvocationReceipt *)_IDE_collectNewCrashReportsInDirectories:(NSArray *)arg1 matchingProcessNames:(NSArray *)arg2;
@end
