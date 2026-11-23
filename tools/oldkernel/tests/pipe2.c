#define _GNU_SOURCE
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <errno.h>
int main(void){
	int f[2]; char b;
	if (pipe2(f, O_NONBLOCK|O_CLOEXEC)) { perror("pipe2"); return 1; }
	int fl = fcntl(f[0], F_GETFL), fd = fcntl(f[0], F_GETFD);
	printf("nonblock=%d cloexec=%d\n", !!(fl&O_NONBLOCK), !!(fd&FD_CLOEXEC));
	fflush(stdout);
	ssize_t n = read(f[0], &b, 1);
	printf("read=%zd errno=%d (%s)\n", n, errno, errno==EAGAIN?"EAGAIN":"other");
	return (fl&O_NONBLOCK) && (fd&FD_CLOEXEC) && n==-1 && errno==EAGAIN ? 0 : 1;
}
