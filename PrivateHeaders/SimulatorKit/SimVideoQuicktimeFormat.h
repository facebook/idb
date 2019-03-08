/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/NSObject.h>

@class NSArray, NSDate;

@interface SimVideoQuicktimeFormat : NSObject
{
    unsigned char _qtFormatType;
    BOOL _fragmented;
    NSDate *_creationDate;
    NSDate *_modificationDate;
    NSArray *_sequenceParameterSets;
    NSArray *_pictureParameterSets;
    double _timeScale;
    struct CGSize _frameSize;
}

+ (double)timeIntervalSinceQuicktimeEpochWithDate:(id)arg1;
+ (id)formatWithType:(unsigned char)arg1;
@property (nonatomic, assign) BOOL fragmented;
@property (nonatomic, assign) double timeScale;
@property (nonatomic, copy) NSArray *pictureParameterSets;
@property (nonatomic, copy) NSArray *sequenceParameterSets;
@property (nonatomic, assign) struct CGSize frameSize;
@property (retain, nonatomic) NSDate *modificationDate;
@property (retain, nonatomic) NSDate *creationDate;
@property (nonatomic, assign) unsigned char qtFormatType;

- (id)dictionaryForMovieFragment;
- (id)dictionaryForMovie;
- (id)dataForHeader;

@end
