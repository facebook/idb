/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class DVTDevice, DVTStackBacktrace, IDERunOperation, IDETestRunner, NSMutableArray, NSString;

@interface _IDETestResultsProcessor : NSObject
{
    BOOL _finished;
    IDETestRunner *_testRunner;
    NSString *_targetArchitecture;
    DVTDevice *_targetDevice;
    IDERunOperation *_operation;
    NSMutableArray *_validatorsStack;
}

+ (void)initialize;
@property(retain) NSMutableArray *validatorsStack; // @synthesize validatorsStack=_validatorsStack;
@property BOOL finished; // @synthesize finished=_finished;
@property(readonly) IDERunOperation *operation; // @synthesize operation=_operation;
@property(retain) DVTDevice *targetDevice; // @synthesize targetDevice=_targetDevice;
@property(retain) NSString *targetArchitecture; // @synthesize targetArchitecture=_targetArchitecture;
@property(retain) IDETestRunner *testRunner; // @synthesize testRunner=_testRunner;

- (BOOL)validateEvent:(int)arg1 error:(id *)arg2;
- (void)initializeValidatorsStack;
- (id)initWithTestRunOperation:(id)arg1 forTestRunner:(id)arg2;
- (void)primitiveInvalidate;

// Remaining properties
@property(retain) DVTStackBacktrace *creationBacktrace;
@property(readonly, copy) NSString *debugDescription;
@property(readonly, copy) NSString *description;
@property(readonly) unsigned long long hash;
@property(readonly) DVTStackBacktrace *invalidationBacktrace;
@property(readonly) Class superclass;
@property(readonly, nonatomic, getter=isValid) BOOL valid;

@end

