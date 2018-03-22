//
//  FBXCTestWatchdogConfigurator.m
//  FBXCTestKit
//
//  Created by Алексеев Владислав on 10.05.2018.
//  Copyright © 2018 Facebook. All rights reserved.
//

#import "FBXCTestWatchdogConfigurator.h"
#import <FBSimulatorControl/FBDefaultsModificationStrategy.h>

@interface FBXCTestWatchdogConfigurator()
@property (nonatomic, copy, readonly) NSArray<NSString *> *bundleIds;
@property (nonatomic, assign, readonly) NSTimeInterval timeout;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@end

@implementation FBXCTestWatchdogConfigurator

+ (instancetype)configurationFromDictionary:(NSDictionary *)dictionary logger:(id<FBControlCoreLogger>)logger
{
  return [self configuratorWithBundleIds:dictionary[@"bundle_ids"]
                                 timeout:[dictionary[@"timeout"] doubleValue]
                                  logger:logger];
}

+ (instancetype)configuratorWithBundleIds:(NSArray<NSString *> *)bundleIds timeout:(NSTimeInterval)timeout logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithBundleIds:bundleIds timeout:timeout logger:logger];
}

- (instancetype)initWithBundleIds:(NSArray<NSString *> *)bundleIds timeout:(NSTimeInterval)timeout logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (self) {
    _bundleIds = [NSArray arrayWithArray:bundleIds];
    _timeout = timeout;
    _logger = logger;
  }
  return self;
}

- (FBFuture *)configureSimulator:(FBSimulator *)simulator
{
  FBWatchdogOverrideModificationStrategy *strategy = [FBWatchdogOverrideModificationStrategy strategyWithSimulator:simulator];
  [self.logger.debug logFormat:@"Applying watchdog timeout of %lu seconds to bundle ids: %@", (NSUInteger)self.timeout, self.bundleIds];
  return [strategy overrideWatchDogTimerForApplications:self.bundleIds timeout:self.timeout];
}

@end
