#define _GNU_SOURCE
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <errno.h>
#include <sys/syscall.h>
/* A call the kernel does not have, then ordinary calls whose results must still be right:
   the tracer has to keep telling syscall entries from exits after an -ENOSYS (2.6.12 reports
   every exit twice, and the repeat of an -ENOSYS exit looks like an entry). */
static int bad;
static void check(int ok, const char *what) { printf("%s: %s\n", ok ? "ok" : "FAIL", what); if (!ok) bad = 1; }
int main(void){
	char file[] = "/tmp/enosys-test";
	unlink(file);
	for (int round = 0; round < 3; round++) {
		/* what busybox touch does: utimensat (2.6.22), then futimesat, which the layer translates */
		errno = 0; long r = syscall(SYS_utimensat, AT_FDCWD, file, 0, 0);
		check(r == -1 && (errno == ENOSYS || errno == ENOENT), "utimensat fails with ENOSYS or ENOENT");
		errno = 0; r = syscall(SYS_futimesat, AT_FDCWD, file, 0);
		check(r == -1 && errno == ENOENT, "futimesat of a missing file fails with ENOENT");
		errno = 0; int fd = open(file, O_CREAT | O_EXCL | O_WRONLY, 0600);
		check(fd >= 0, "open creates the file");
		if (fd >= 0) close(fd);
		errno = 0; r = syscall(SYS_futimesat, AT_FDCWD, file, 0);
		check(r == 0, "futimesat of the file works");
		check(unlink(file) == 0, "unlink");
	}
	return bad;
}
