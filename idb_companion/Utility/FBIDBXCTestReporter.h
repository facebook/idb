/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <idbGRPC/idb.grpc.pb.h>
#import <XCTestBootstrap/FBXCTestReporter.h>
#import <FBControlCore/FBControlCore.h>

using idb::CompanionService;
using grpc::Status;
using grpc::ServerContext;

NS_ASSUME_NONNULL_BEGIN
/**
 Bridges from the FBXCTestReporter protocol to a GRPC result writer.
 This also keeps track of the terminal condition of the reporter, so this can be used to know when reporting has fully terminated.
 */
@interface FBIDBXCTestReporter : NSObject <FBXCTestReporter, FBDataConsumer>

#pragma mark Initializers

/**
 The Designated Initializer

 @param writer the response writer to use.
 @param queue the queue to serialize work on.
 @param reportAttachments whether to return activity attachments
 @param logger the logger to log to.
 */
- (instancetype)initWithResponseWriter:(grpc::ServerWriter<idb::XctestRunResponse> *)writer reportAttachments:(BOOL)reportAttachments queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

#pragma mark Properties

/**
 A Future that resolves with an integer representation of XctestRunResponse_TestRunInfo_Status upon termination.
 */
@property (nonatomic, strong, readonly) FBFuture<NSNumber *> *reportingTerminated;

/**
 The Result Bundle Path (if any)
 */
@property (nonatomic, copy, nullable, readwrite) NSString *resultBundlePath;

/**
 Coverage file path
 */
@property (nonatomic, copy, nullable, readwrite) NSString *coveragePath;

/**
 App binary path
 */
@property (nonatomic, copy, nullable, readwrite) NSString *binaryPath;

@end

NS_ASSUME_NONNULL_END
