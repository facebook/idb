/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@class NSArray, NSString, NSURL;

@protocol XCTMessagingRole_SiriAutomation
- (void)_XCT_injectVoiceRecognitionAudioInputPaths:(NSArray *)arg1 completion:(void (^)(_Bool, NSError *))arg2;
- (void)_XCT_injectAssistantRecognitionStrings:(NSArray *)arg1 completion:(void (^)(_Bool, NSError *))arg2;
- (void)_XCT_startSiriUIRequestWithAudioFileURL:(NSURL *)arg1 completion:(void (^)(_Bool, NSError *))arg2;
- (void)_XCT_startSiriUIRequestWithText:(NSString *)arg1 completion:(void (^)(_Bool, NSError *))arg2;
- (void)_XCT_requestSiriEnabledStatus:(void (^)(_Bool, NSError *))arg1;
@end

