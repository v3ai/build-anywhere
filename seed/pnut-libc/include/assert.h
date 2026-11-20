/* assert.h: build-anywhere shell tier (pnut-sh). */
#ifndef _BA_SH_ASSERT_H
#define _BA_SH_ASSERT_H
#ifdef NDEBUG
#define assert(e) 0
#else
void ba_sh_assert(int ok, char *expr, char *file, int line);
#define assert(e) ba_sh_assert((e) != 0, #e, __FILE__, __LINE__)
#endif
#endif
