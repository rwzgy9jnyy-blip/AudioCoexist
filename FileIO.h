#pragma once
#import <Foundation/Foundation.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static inline bool ASCWriteAll(int fd, NSData *data) {
    const char *bytes = (const char *)data.bytes;
    size_t remaining = data.length;
    while (remaining) {
        ssize_t count = write(fd, bytes, remaining);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return false;
        bytes += count;
        remaining -= (size_t)count;
    }
    return true;
}

// Do not follow a symlink or block opening a FIFO in a shared temporary directory.
static inline int ASCOpenRegular(NSString *path, int flags, mode_t mode) {
    int fd = open(path.fileSystemRepresentation,
        flags | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, mode);
    if (fd < 0) return -1;
    struct stat info;
    if (fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) || fchmod(fd, mode) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

// The final file never has a partially written body or a temporary public mode.
static inline bool ASCWriteAtomic(NSString *path, NSData *data, mode_t mode) {
    if (!data) return false;
    char *temporary = strdup([[path stringByAppendingString:@".XXXXXX"] fileSystemRepresentation]);
    if (!temporary) return false;
    int fd = mkstemp(temporary);
    if (fd < 0) { free(temporary); return false; }
    bool result = fcntl(fd, F_SETFD, FD_CLOEXEC) != -1 &&
        fchmod(fd, mode) == 0 && ASCWriteAll(fd, data);
    if (close(fd) != 0) result = false;
    if (result) result = rename(temporary, path.fileSystemRepresentation) == 0;
    if (!result) unlink(temporary);
    free(temporary);
    return result;
}
