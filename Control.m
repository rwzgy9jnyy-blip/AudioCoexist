#import <Foundation/Foundation.h>
#import <roothide.h>
#include <sys/file.h>
#include "Settings.h"
#include "FileIO.h"

static int usage(void) {
    fprintf(stderr, "usage: audio-coexist on|off|record-on|record-off|status|dump\n");
    return 2;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 1 || argc > 2) return usage();
        NSString *action = argc == 2 ? @(argv[1]) : @"status";
        NSString *key = nil;
        BOOL value = YES;
        if ([action isEqual:@"on"]) key = @"Enabled";
        else if ([action isEqual:@"off"]) { key = @"Enabled"; value = NO; }
        else if ([action isEqual:@"record-on"]) key = @"Recording";
        else if ([action isEqual:@"record-off"]) { key = @"Recording"; value = NO; }
        else if (![action isEqual:@"status"] && ![action isEqual:@"dump"]) return usage();

        NSString *path = jbroot(ASCSettingsPath);
        NSDictionary *settings;
        if (key) {
            NSError *error = nil;
            if (![NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
                withIntermediateDirectories:YES attributes:nil error:&error]) {
                fprintf(stderr, "cannot create settings directory (run as root)\n");
                return 1;
            }
            // Serialize read/modify/write across separate CLI processes.
            int fd = ASCOpenRegular([path stringByAppendingString:@".lock"], O_WRONLY | O_CREAT, 0600);
            if (fd < 0) { fprintf(stderr, "cannot open settings lock (run as root)\n"); return 1; }
            int locked;
            do { locked = flock(fd, LOCK_EX); } while (locked != 0 && errno == EINTR);
            if (locked != 0) { close(fd); fprintf(stderr, "cannot lock settings\n"); return 1; }
            NSMutableDictionary *updated = [ASCReadSettings(path) mutableCopy];
            updated[key] = @(value);
            NSData *data = [NSPropertyListSerialization dataWithPropertyList:updated
                format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
            bool written = ASCWriteAtomic(path, data, 0644);
            close(fd);
            if (!written) { fprintf(stderr, "cannot write settings (run as root)\n"); return 1; }
            settings = updated;
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                CFSTR("com.codex.audiocoexistserver/settingsChanged"), NULL, NULL, true);
        } else {
            settings = ASCReadSettings(path);
            if ([action isEqual:@"dump"]) {
                CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                    CFSTR("com.codex.audiocoexistserver/dump"), NULL, NULL, true);
            }
        }
        unsigned flags = ASCSettingsFlags(settings);
        printf("enabled=%d recording=%d; scope=audiomxd-only\n",
            !!(flags & ASCEnabled), !!(flags & ASCRecording));
    }
    return 0;
}
