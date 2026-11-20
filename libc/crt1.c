/*
 * crt1.c: program entry point for the build-anywhere libc (Linux x86_64 and
 * i386). The kernel starts a process at _start with argc, argv and envp on
 * the stack; this passes them to main and exits with its result. On i386
 * it also sets the x87 FPU to double precision (see below).
 */
extern char **environ;
int main();
void exit(int status);
void __ba_start_c(long *sp);

#if defined(__x86_64__)
__asm__(
    ".text\n"
    ".globl _start\n"
    "_start:\n"
    "  xor %rbp, %rbp\n"
    "  mov %rsp, %rdi\n"
    "  and $-16, %rsp\n"
    "  call __ba_start_c\n"
    "  hlt\n"
);
#elif defined(__i386__)
__asm__(
    ".text\n"
    ".globl _start\n"
    "_start:\n"
    "  xor %ebp, %ebp\n"
    /* Make the x87 FPU round every result to double (53 bits), as FreeBSD
       does: TinyCC computes with the x87 on i386, and the libc's math and
       printf rely on each double operation being rounded once. */
    "  push $0x027f\n"
    "  fldcw (%esp)\n"
    "  add $4, %esp\n"
    "  mov %esp, %eax\n"
    "  and $-16, %esp\n"
    "  sub $12, %esp\n"
    "  push %eax\n"
    "  call __ba_start_c\n"
    "  hlt\n"
);
#endif

void __ba_start_c(long *sp)
{
    int argc = (int)sp[0];
    char **argv = (char **)(sp + 1);
    environ = argv + argc + 1;
    exit(main(argc, argv, environ));
}
