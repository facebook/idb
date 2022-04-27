/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import "FBCrashLogParser.h"
#import "FBConcatedJsonParser.h"
#import "FBCrashLog.h"

@implementation FBConcatedJSONCrashLogParser

-(void)parseCrashLogFromString:(NSString *)str executablePathOut:(NSString **)executablePathOut identifierOut:(NSString **)identifierOut processNameOut:(NSString **)processNameOut parentProcessNameOut:(NSString **)parentProcessNameOut processIdentifierOut:(pid_t *)processIdentifierOut parentProcessIdentifierOut:(pid_t *)parentProcessIdentifierOut dateOut:(NSDate **)dateOut error:(NSError **)error {
  
  NSDictionary<NSString *, id> *parsedReport = [FBConcatedJsonParser parseConcatenatedJSONFromString:str error:error];
  if (!parsedReport) {
    return;
  }
  
  *executablePathOut = parsedReport[@"procPath"];
  
  // Name and identifier is the same thing
  *processNameOut = parsedReport[@"procName"];
  *identifierOut = parsedReport[@"procName"];
  if ([parsedReport valueForKey:@"pid"]) {
    *processIdentifierOut = ((NSNumber *)parsedReport[@"pid"]).intValue;
  }
  
  *parentProcessNameOut = parsedReport[@"parentProc"];
  if ([parsedReport valueForKey:@"parentPid"]) {
    *parentProcessIdentifierOut = ((NSNumber *)parsedReport[@"parentPid"]).intValue;
  }
  if ([parsedReport valueForKey:@"captureTime"]) {
    NSString *dateString = parsedReport[@"captureTime"];
    *dateOut = [FBCrashLog.dateFormatter dateFromString:dateString];
  }
  
}

@end


@implementation FBPlainTextCrashLogParser

static NSUInteger MaxLineSearch = 20;

-(void)parseCrashLogFromString:(NSString *)str executablePathOut:(NSString **)executablePathOut identifierOut:(NSString **)identifierOut processNameOut:(NSString **)processNameOut parentProcessNameOut:(NSString **)parentProcessNameOut processIdentifierOut:(pid_t *)processIdentifierOut parentProcessIdentifierOut:(pid_t *)parentProcessIdentifierOut dateOut:(NSDate **)dateOut error:(NSError **)error {
  
  // Buffers for the sscanf
  size_t lineSize = sizeof(char) * 4098;
  const char *line = malloc(lineSize);
  char value[lineSize];

  NSUInteger length = [str length];
  NSUInteger paraStart = 0, paraEnd = 0, contentsEnd = 0;
  NSRange currentRange;
  NSUInteger linesParsed = 0;
  
  while (paraEnd < length && linesParsed < MaxLineSearch)
  {
    linesParsed += 1;
    [str getParagraphStart:&paraStart end:&paraEnd contentsEnd:&contentsEnd forRange:NSMakeRange(paraEnd, 0)];
    currentRange = NSMakeRange(paraStart, contentsEnd - paraStart);
    line = [[str substringWithRange:currentRange] UTF8String];
    
    if (sscanf(line, "Process: %s [%d]", value, processIdentifierOut) > 0) {
      *processNameOut = [[NSString alloc] initWithCString:value encoding:NSUTF8StringEncoding];
      continue;
    }
    if (sscanf(line, "Identifier: %s", value) > 0) {
      *identifierOut = [[NSString alloc] initWithCString:value encoding:NSUTF8StringEncoding];
      continue;
    }
    if (sscanf(line, "Parent Process: %s [%d]", value, parentProcessIdentifierOut) > 0) {
      *parentProcessNameOut = [[NSString alloc] initWithCString:value encoding:NSUTF8StringEncoding];
      continue;
    }
    if (sscanf(line, "Path: %s", value) > 0) {
      *executablePathOut = [[NSString alloc] initWithCString:value encoding:NSUTF8StringEncoding];
      continue;
    }
    if (sscanf(line, "Date/Time: %[^\n]", value) > 0) {
      NSString *dateString = [[NSString alloc] initWithCString:value encoding:NSUTF8StringEncoding];
      *dateOut = [FBCrashLog.dateFormatter dateFromString:dateString];
      continue;
    }
  }
}

@end
