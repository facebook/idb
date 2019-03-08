/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@interface SimLocalThrowable : NSObject
{
    id _data;
}

+ (id)throwableWithData:(id)arg1;
@property (retain, nonatomic) id data;

- (id)initWithData:(id)arg1;

@end
