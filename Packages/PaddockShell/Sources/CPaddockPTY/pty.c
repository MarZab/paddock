#define _GNU_SOURCE
#include "CPaddockPTY.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

int paddock_pty_open(char *name, size_t name_len) {
    int master = posix_openpt(O_RDWR | O_NOCTTY);
    if (master < 0) return -1;
    if (grantpt(master) != 0 || unlockpt(master) != 0 || ptsname_r(master, name, name_len) != 0) {
        int saved = errno;
        close(master);
        errno = saved;
        return -1;
    }
    fcntl(master, F_SETFD, FD_CLOEXEC);
    return master;
}

int paddock_pty_set_size(int fd, unsigned short rows, unsigned short cols) {
    struct winsize size = { .ws_row = rows, .ws_col = cols, .ws_xpixel = 0, .ws_ypixel = 0 };
    return ioctl(fd, TIOCSWINSZ, &size);
}

pid_t paddock_pty_spawn(const char *path, char *const argv[], char *const envp[], const char *slave, int *error) {
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    posix_spawn_file_actions_init(&actions);
    posix_spawnattr_init(&attributes);

    // Opened in the child after setsid, so it becomes the controlling terminal.
    posix_spawn_file_actions_addopen(&actions, 0, slave, O_RDWR, 0);
    posix_spawn_file_actions_adddup2(&actions, 0, 1);
    posix_spawn_file_actions_adddup2(&actions, 0, 2);

    short flags = POSIX_SPAWN_SETSID | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK;
#ifdef POSIX_SPAWN_CLOEXEC_DEFAULT
    flags |= POSIX_SPAWN_CLOEXEC_DEFAULT;
#endif
    posix_spawnattr_setflags(&attributes, flags);
    sigset_t all, none;
    sigfillset(&all);
    sigemptyset(&none);
    posix_spawnattr_setsigdefault(&attributes, &all);
    posix_spawnattr_setsigmask(&attributes, &none);

    pid_t pid = -1;
    int result = posix_spawn(&pid, path, &actions, &attributes, argv, envp);
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attributes);
    if (result != 0) {
        *error = result;
        return -1;
    }
    return pid;
}
