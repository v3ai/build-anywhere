/* string.h: build-anywhere shell tier (pnut-sh). */
#ifndef _BA_SH_STRING_H
#define _BA_SH_STRING_H
#include <stddef.h>
int strlen(char *s);
char *strcpy(char *d, char *s);
char *strncpy(char *d, char *s, int n);
char *strcat(char *d, char *s);
char *strncat(char *d, char *s, int n);
int strcmp(char *a, char *b);
int strncmp(char *a, char *b, int n);
char *strchr(char *s, int c);
char *strrchr(char *s, int c);
char *strstr(char *h, char *n);
int strspn(char *s, char *set);
int strcspn(char *s, char *set);
char *strpbrk(char *s, char *set);
char *strdup(char *s);
void *memcpy(void *d, void *s, int n);
void *memmove(void *d, void *s, int n);
void *memset(void *d, int c, int n);
int memcmp(void *a, void *b, int n);
void *memchr(void *s, int c, int n);
#endif
