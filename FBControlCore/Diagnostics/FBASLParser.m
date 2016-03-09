/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBASLParser.h"

#include <asl.h>

#import "FBDiagnostic.h"
#import "FBProcessInfo.h"

static BOOL WriteOutputToFilePath(const char *filePath, asl_object_t aslFile, pid_t processIdentifier)
{
  char pidString[10];
  if (snprintf(pidString, 10, "%d", processIdentifier) < 1) {
    return NO;
  }

  asl_object_t query = asl_new(ASL_TYPE_QUERY);
  asl_set_query(query, ASL_KEY_PID, pidString, ASL_QUERY_OP_EQUAL | ASL_QUERY_OP_NUMERIC);
  aslresponse response = asl_search(aslFile, query);

  aslmsg item = asl_next(response);
  if (!item) {
    asl_close(query);
    return NO;
  }

  FILE *file = fopen(filePath, "w");
  while (item) {
    const char *message = asl_format(item, ASL_MSG_FMT_STD, ASL_TIME_FMT_LCL, ASL_ENCODE_SAFE);
    fputs(message, file);
    free((void *)message);
    item = asl_next(response);
  }

  asl_close(query);
  fclose(file);
  return YES;
}

@interface FBASLParser ()

@property (nonatomic, copy, readonly) NSString *path;
@property (nonatomic, assign, readwrite) asl_object_t asl;

@end

@implementation FBASLParser

#pragma mark Initializers

+ (instancetype)parserForPath:(NSString *)path
{
  NSParameterAssert(path);
  asl_object_t asl = asl_open_path(path.UTF8String, 0);
  if (asl == NULL) {
    return nil;
  }
  asl_set_filter(asl, ASL_FILTER_MASK_UPTO(ASL_LEVEL_DEBUG));
  return [[self alloc] initWithASLObject:asl];
}

- (instancetype)initWithASLObject:(asl_object_t)asl
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _asl = asl;

  return self;
}

- (void)dealloc
{
  asl_close(_asl);
  _asl = NULL;
}

#pragma mark Public

- (FBDiagnostic *)diagnosticForProcessInfo:(FBProcessInfo *)processInfo logBuilder:(FBDiagnosticBuilder *)logBuilder
{
  return [[[[logBuilder
    updateShortName:processInfo.processName]
    updateFileType:@"log"]
    updatePathFromBlock:^ BOOL (NSString *outputPath) {
      return WriteOutputToFilePath(outputPath.UTF8String, self.asl, processInfo.processIdentifier);
    }]
    build];
}

@end
