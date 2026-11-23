#pragma once
#import <Foundation/Foundation.h>
#include <stdbool.h>

enum { ASCEnabled = 1, ASCRecording = 2, ASCDefaults = ASCEnabled | ASCRecording };
static NSString *const ASCSettingsPath = @"/var/mobile/Library/Preferences/com.codex.audiocoexistserver.plist";

static inline bool ASCSettingBool(id value, bool fallback) {
    if ([value isKindOfClass:NSNumber.class]) return [value boolValue];
    if ([value isKindOfClass:NSString.class]) {
        NSString *text = [[value stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
        if ([@[@"true", @"yes", @"1"] containsObject:text]) return true;
        if ([@[@"false", @"no", @"0"] containsObject:text]) return false;
    }
    return fallback;
}

static inline NSDictionary *ASCReadSettings(NSString *path) {
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:path];
    return [settings isKindOfClass:NSDictionary.class] ? settings : @{};
}

static inline unsigned ASCSettingsFlags(id settings) {
    if (![settings isKindOfClass:NSDictionary.class]) return ASCDefaults;
    return (ASCSettingBool(settings[@"Enabled"], true) ? ASCEnabled : 0) |
        (ASCSettingBool(settings[@"Recording"], true) ? ASCRecording : 0);
}
