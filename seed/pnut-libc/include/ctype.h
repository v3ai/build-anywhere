/* ctype.h: build-anywhere shell tier (pnut-sh). */
#ifndef _BA_SH_CTYPE_H
#define _BA_SH_CTYPE_H
int isdigit(int c);
int isalpha(int c);
int isalnum(int c);
int isspace(int c);
int isupper(int c);
int islower(int c);
int isxdigit(int c);
int isprint(int c);
int ispunct(int c);
int iscntrl(int c);
int isgraph(int c);
int toupper(int c);
int tolower(int c);
#endif
