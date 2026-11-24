#define _GNU_SOURCE
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/syscall.h>
/* *at calls through a directory fd, as the layer has to translate them on kernels < 2.6.16.
   Every check must hold on a kernel that has the call natively too. */
static int bad;
static void check(int ok, const char *what) { printf("%s: %s\n", ok ? "ok" : "FAIL", what); if (!ok) bad = 1; }
int main(void){
	char dir[] = "/tmp/at-testXXXXXX";
	if (!mkdtemp(dir)) { perror("mkdtemp"); return 1; }
	int d = open(dir, O_RDONLY | O_DIRECTORY);
	if (d < 0) { perror("open dir"); return 1; }
	/* dirfd-relative names of every length 1..70, at every alignment in the buffer */
	int paths = 1;
	for (int len = 1; len <= 70 && paths; len++) {
		for (int off = 0; off < 8 && paths; off++) {
			char buf[160]; memset(buf, 'x', sizeof buf);
			char *name = buf + 8 + off;
			memset(name, 'a' + len % 26, len); name[len] = 0; name[0] = 'a' + off;
			int f = openat(d, name, O_CREAT | O_WRONLY | O_EXCL, 0600);
			struct stat st;
			if (f < 0 || fstatat(d, name, &st, 0) || unlinkat(d, name, 0)) { printf("len=%d off=%d errno=%d\n", len, off, errno); paths = 0; }
			if (f >= 0) close(f);
		}
	}
	check(paths, "openat/fstatat/unlinkat names of 1..70 bytes at every alignment");
	/* linkat: a flag the kernel (2.6.16, 2.6.17) refuses must not turn into a hardlink of the symlink */
	int f = openat(d, "target", O_CREAT | O_WRONLY, 0600); close(f);
	check(symlinkat("target", d, "sl") == 0, "symlinkat");
	check(linkat(d, "target", d, "plain", 0) == 0, "linkat flags 0");
	int r = linkat(d, "sl", d, "followed", AT_SYMLINK_FOLLOW), e = errno;
	if (r == 0) {
		struct stat a, b; fstatat(d, "target", &a, 0); fstatat(d, "followed", &b, AT_SYMLINK_NOFOLLOW);
		check(a.st_ino == b.st_ino && S_ISREG(b.st_mode), "linkat AT_SYMLINK_FOLLOW links the target");
	} else check(e == EINVAL, "linkat AT_SYMLINK_FOLLOW refused with EINVAL");
	/* a syscall number the kernel does not have must fail, not hand its own number back */
	long n = syscall(279, 0, 0, 0, 0, 0, 0);
	check(n != 279, "syscall 279 does not echo its number");
	return bad;
}
