/*
 * ba_va.c: run-time support for <stdarg.h> under TinyCC on x86_64.
 *
 * TinyCC expands va_start(ap) to __va_start(ap, frame) and va_arg(ap, T) to
 * *(T *)__va_arg(ap, class, sizeof(T), alignof(T)). On entry, a variadic
 * function compiled by TinyCC stores three 32-bit words at frame - 16 (the
 * initial gp_offset and fp_offset of the System V va_list, then the offset
 * from frame to the first argument passed on the stack) and spills the six
 * integer and eight SSE argument registers into a 176-byte area that ends at
 * frame - 16. va_list itself has the System V AMD64 layout.
 *
 * Part of build-anywhere. Written for build-anywhere, so that programs
 * built by the bootstrapped TinyCC contain only MIT-licensed run-time code
 * besides TinyCC's libtcc1 (which carries a linking exception).
 */
#if defined(__x86_64__)

void abort(void);

struct ba_va_list {
    unsigned int gp_offset;     /* next integer register, 0..48 */
    unsigned int fp_offset;     /* next SSE register, 48..176 */
    char *overflow_arg_area;    /* next argument passed on the stack */
    char *reg_save_area;
};

enum { BA_VA_GEN_REG, BA_VA_FLOAT_REG, BA_VA_STACK };

#define BA_GP_END 48
#define BA_FP_END (48 + 8 * 16)
#define BA_SAVE_AREA 176

void __va_start(struct ba_va_list *ap, char *frame)
{
    const unsigned int *header = (const unsigned int *)(frame - 16);
    ap->gp_offset = header[0];
    ap->fp_offset = header[1];
    ap->overflow_arg_area = frame + header[2];
    ap->reg_save_area = frame - 16 - BA_SAVE_AREA;
}

static char *from_stack(struct ba_va_list *ap, int size, int align)
{
    /* Same stepping as TinyCC's code generator uses when it passes the
       arguments: advance by the size, then align the end. */
    long a = (long)align;
    ap->overflow_arg_area += size;
    ap->overflow_arg_area = (char *)(((long)ap->overflow_arg_area + a - 1) & -a);
    return ap->overflow_arg_area - size;
}

void *__va_arg(struct ba_va_list *ap, int arg_class, int size, int align)
{
    size = (size + 7) & ~7;
    align = (align + 7) & ~7;
    if (arg_class == BA_VA_GEN_REG) {
        if (ap->gp_offset + (unsigned int)size <= BA_GP_END) {
            ap->gp_offset += (unsigned int)size;
            return ap->reg_save_area + ap->gp_offset - size;
        }
        return from_stack(ap, size, align);
    }
    if (arg_class == BA_VA_FLOAT_REG) {
        if (ap->fp_offset < BA_FP_END) {
            ap->fp_offset += 16;
            return ap->reg_save_area + ap->fp_offset - 16;
        }
        return from_stack(ap, 8, align);
    }
    if (arg_class == BA_VA_STACK)
        return from_stack(ap, size, align);
    abort();
    return 0;
}

#else
/* Other targets need no run-time support for <stdarg.h>. */
typedef int ba_va_unused;
#endif
