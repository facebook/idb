/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class NSArray, NSString;

@interface DVTLogAspect : NSObject
{
    NSString *_name;
    BOOL _signalInstruments;
    BOOL _takeTimeProfile;
    int _logLevel;
    NSArray *_activeLoggers;
}

+ (id)logAspectWithName:(id)arg1;
+ (id)allAspects;
+ (int)defaultLogLevel;
+ (void)initialize;
@property(copy) NSArray *activeLoggers; // @synthesize activeLoggers=_activeLoggers;
@property BOOL takeTimeProfile; // @synthesize takeTimeProfile=_takeTimeProfile;
@property BOOL signalInstruments; // @synthesize signalInstruments=_signalInstruments;
@property int logLevel; // @synthesize logLevel=_logLevel;
@property(readonly) NSString *name; // @synthesize name=_name;

- (void)_logAndOutdentAtLogLevel:(int)arg1 withFormat:(id)arg2;
- (void)_logAndIndentAtLogLevel:(int)arg1 withFormat:(id)arg2;
- (void)_logAtLogLevel:(int)arg1 withFormat:(id)arg2;
- (id)initWithName:(id)arg1 logLevel:(int)arg2 signalInstruments:(BOOL)arg3 takeTimeProfile:(BOOL)arg4 activeLoggers:(id)arg5;
- (id)init;

@end

