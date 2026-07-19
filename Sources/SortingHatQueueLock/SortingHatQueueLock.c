#include "SortingHatQueueLock.h"

#include <errno.h>
#include <sys/file.h>

int sortinghat_queue_lock(int descriptor) {
    int result;
    do {
        result = flock(descriptor, LOCK_EX);
    } while (result != 0 && errno == EINTR);
    return result;
}

int sortinghat_queue_unlock(int descriptor) {
    return flock(descriptor, LOCK_UN);
}
