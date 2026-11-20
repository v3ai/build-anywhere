/* setjmp.h: build-anywhere libc. */
#ifndef _BA_SETJMP_H
#define _BA_SETJMP_H
typedef long jmp_buf[8];
int setjmp(jmp_buf env);
void longjmp(jmp_buf env, int val);
#define _setjmp setjmp
#endif
