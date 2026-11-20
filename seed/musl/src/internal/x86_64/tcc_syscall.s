/* build-anywhere: __tcc_syscall6(n, a1, a2, a3, a4, a5, a6) for code built
 * by TinyCC (see arch/x86_64/syscall_arch.h). Moves the System V call
 * arguments into the Linux syscall registers. */
.global __tcc_syscall6
.hidden __tcc_syscall6
.type __tcc_syscall6,@function
__tcc_syscall6:
	mov %rdi,%rax
	mov %rsi,%rdi
	mov %rdx,%rsi
	mov %rcx,%rdx
	mov %r8,%r10
	mov %r9,%r8
	mov 8(%rsp),%r9
	syscall
	ret
