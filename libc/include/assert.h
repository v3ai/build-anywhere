/* assert.h: build-anywhere libc. May be included repeatedly (C89 7.2). */
#undef assert
#ifdef NDEBUG
#define assert(e) ((void)0)
#else
void __ba_assert_fail(const char *expr, const char *file, int line);
#define assert(e) ((e) ? (void)0 : __ba_assert_fail(#e, __FILE__, __LINE__))
#endif
