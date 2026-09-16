/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FBNetworkConfigurationTestRuntime : NSObject
@property (nonatomic) BOOL libraryAvailable;
@property (nonatomic) BOOL storeAvailable;
@property (nonatomic) BOOL writeSucceeds;
@property (nonatomic) BOOL notifySucceeds;
@property (nonatomic, copy) NSSet<NSString *> *missingSymbols;
@property (nullable, nonatomic, copy) NSDictionary<NSString *, id> *configuration;
@property (nonatomic, readonly) NSMutableArray<NSString *> *operations;
@property (nonatomic, readonly) NSMutableArray<NSString *> *keys;
@property (nonatomic, readonly) NSMutableArray<NSDictionary<NSString *, id> *> *writes;
@property (nonatomic, readonly, copy) NSString *output;
- (int)runService:(NSString *)service action:(NSString *)action arguments:(NSArray<NSString *> *)arguments
  NS_SWIFT_NAME(run(service:action:arguments:));
@end

NS_ASSUME_NONNULL_END
