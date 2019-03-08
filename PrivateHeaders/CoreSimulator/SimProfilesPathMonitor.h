/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class NSArray, NSMutableArray, NSMutableDictionary, SimServiceContext;
@protocol OS_dispatch_queue;

@interface SimProfilesPathMonitor : NSObject
{
    NSObject<OS_dispatch_queue> *_monitorQueue;
    NSMutableArray *_leafMonitorSources;
    NSMutableDictionary *_monitoredPathsDict;
    SimServiceContext *_serviceContext;
}

+ (id)profilesPathMonitorForContext:(id)arg1;
@property (nonatomic, weak) SimServiceContext *serviceContext;
@property (retain, nonatomic) NSMutableDictionary *monitoredPathsDict;
@property (retain, nonatomic) NSMutableArray *leafMonitorSources;
@property (retain, nonatomic) NSObject<OS_dispatch_queue> *monitorQueue;

- (void)_monitorProfilesSubDirectory:(int)arg1 path:(id)arg2 updateBlock:(CDUnknownBlockType)arg3;
- (void)_monitorProfilesDirectory:(int)arg1 path:(id)arg2 forSubDirectory:(id)arg3 updateBlock:(CDUnknownBlockType)arg4;
- (void)_monitorProfilesDirectory:(int)arg1 path:(id)arg2;
- (void)_monitorProfilesParentDirectory:(int)arg1 nextPathComponent:(id)arg2 path:(id)arg3;
- (void)_monitorProfilesPath:(id)arg1;
- (void)fence;
@property (nonatomic, copy, readonly) NSArray *monitoredPaths;
- (void)monitorProfilesPath:(id)arg1;
- (void)monitorDefaultProfilePaths;
- (id)initWithContext:(id)arg1;

@end

