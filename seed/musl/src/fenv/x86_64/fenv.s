.global feclearexcept
.type feclearexcept,@function
feclearexcept:
		# maintain exceptions in the sse mxcsr, clear x87 exceptions
	mov %edi,%ecx
	and $0x3f,%ecx
	fnstsw %ax
	test %eax,%ecx
	jz 1f
	fnclex
1:	.byte 0x0f,0xae,0x5c,0x24,0xf8 /* stmxcsr -8(%rsp) */
	and $0x3f,%eax
	or %eax,-8(%rsp)
	test %ecx,-8(%rsp)
	jz 1f
	not %ecx
	and %ecx,-8(%rsp)
	.byte 0x0f,0xae,0x54,0x24,0xf8 /* ldmxcsr -8(%rsp) */
1:	xor %eax,%eax
	ret

.global feraiseexcept
.type feraiseexcept,@function
feraiseexcept:
	and $0x3f,%edi
	.byte 0x0f,0xae,0x5c,0x24,0xf8 /* stmxcsr -8(%rsp) */
	or %edi,-8(%rsp)
	.byte 0x0f,0xae,0x54,0x24,0xf8 /* ldmxcsr -8(%rsp) */
	xor %eax,%eax
	ret

.global __fesetround
.hidden __fesetround
.type __fesetround,@function
__fesetround:
	push %rax
	xor %eax,%eax
	mov %edi,%ecx
	fnstcw (%rsp)
	andb $0xf3,1(%rsp)
	or %ch,1(%rsp)
	fldcw (%rsp)
	.byte 0x0f,0xae,0x1c,0x24 /* stmxcsr (%rsp) */
	shl $3,%ch
	andb $0x9f,1(%rsp)
	or %ch,1(%rsp)
	.byte 0x0f,0xae,0x14,0x24 /* ldmxcsr (%rsp) */
	pop %rcx
	ret

.global fegetround
.type fegetround,@function
fegetround:
	push %rax
	.byte 0x0f,0xae,0x1c,0x24 /* stmxcsr (%rsp) */
	pop %rax
	shr $3,%eax
	and $0xc00,%eax
	ret

.global fegetenv
.type fegetenv,@function
fegetenv:
	xor %eax,%eax
	fnstenv (%rdi)
	.byte 0x0f,0xae,0x5f,0x1c /* stmxcsr 28(%rdi) */
	ret

.global fesetenv
.type fesetenv,@function
fesetenv:
	xor %eax,%eax
	inc %rdi
	jz 1f
	fldenv -1(%rdi)
	.byte 0x0f,0xae,0x57,0x1b /* ldmxcsr 27(%rdi) */
	ret
1:	push %rax
	push %rax
	pushq $0xffff
	pushq $0x37f
	fldenv (%rsp)
	pushq $0x1f80
	.byte 0x0f,0xae,0x14,0x24 /* ldmxcsr (%rsp) */
	add $40,%rsp
	ret

.global fetestexcept
.type fetestexcept,@function
fetestexcept:
	and $0x3f,%edi
	push %rax
	.byte 0x0f,0xae,0x1c,0x24 /* stmxcsr (%rsp) */
	pop %rsi
	fnstsw %ax
	or %esi,%eax
	and %edi,%eax
	ret
