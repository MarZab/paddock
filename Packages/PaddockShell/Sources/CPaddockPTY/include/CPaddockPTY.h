#ifndef CPADDOCKPTY_H
#define CPADDOCKPTY_H

#include <stddef.h>
#include <sys/types.h>

/// Opens a pseudo-terminal master (close-on-exec), grants and unlocks it, and writes the slave's
/// path into `name`. Returns the master descriptor, or -1 with errno set.
int paddock_pty_open(char *name, size_t name_len);

/// Sets the terminal size. Returns 0, or -1 with errno set.
int paddock_pty_set_size(int fd, unsigned short rows, unsigned short cols);

/// Starts `path` in a new session with the slave terminal as stdin, stdout, and stderr, default
/// signal handlers, and an empty signal mask. On macOS no other descriptors are inherited.
/// Returns the child's pid, or -1 with the error in `*error`.
pid_t paddock_pty_spawn(const char *path, char *const argv[], char *const envp[], const char *slave, int *error);

#endif
