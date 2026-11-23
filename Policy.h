#pragma once
#include <stdbool.h>
typedef enum { ASCUnsupported, ASCPlayback, ASCRecord } ASCCategory;
static inline bool ASCEligible(bool enabled, bool recordingEnabled,
    bool permittedClient, bool protectedSession, bool defaultRoute,
    bool defaultMode, bool playbackMode, ASCCategory category) {
    if (!enabled || !permittedClient || protectedSession || !defaultRoute) return false;
    if (category == ASCPlayback) return defaultMode || playbackMode;
    return category == ASCRecord && recordingEnabled && defaultMode;
}
