/* LD_PRELOAD: count live MetaWaylandCursorSurface / MetaCursorWayland objects
 * (created minus disposed, via weak refs) and write them to $LP_COUNT_FILE. */
#define _GNU_SOURCE
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
typedef unsigned long GType;
typedef struct { GType g_type; } GTypeClass;
typedef struct { GTypeClass *g_class; } GTypeInstance;
typedef struct { const char *name; void *value[3]; } GValueStub;
extern void *g_object_new_valist (GType, const char *, va_list);
extern void *g_object_new_with_properties (GType, unsigned, const char **, const void *);
extern const char *g_type_name (GType);
extern void g_object_weak_ref (void *, void (*)(void *, void *), void *);
static int created[2], live[2], peak[2];
static const char *names[2] = { "MetaWaylandCursorSurface", "MetaCursorWayland" };
static void gone (void *data, void *obj) { __atomic_sub_fetch (&live[(long) data], 1, __ATOMIC_SEQ_CST); }
static void track (void *o) {
  if (!o) return;
  const char *n = g_type_name (((GTypeInstance *) o)->g_class->g_type);
  for (long i = 0; i < 2; i++)
    if (n && !strcmp (n, names[i])) {
      __atomic_add_fetch (&created[i], 1, __ATOMIC_SEQ_CST);
      int l = __atomic_add_fetch (&live[i], 1, __ATOMIC_SEQ_CST);
      if (l > peak[i]) peak[i] = l;
      g_object_weak_ref (o, gone, (void *) i);
    } }
void *g_object_new (GType t, const char *first, ...) {
  va_list ap; va_start (ap, first);
  void *o = g_object_new_valist (t, first, ap);
  va_end (ap); track (o); return o; }
static void *loop (void *a) {
  const char *p = getenv ("LP_COUNT_FILE");
  for (;;) { usleep (200000);
    FILE *f = fopen (p, "w");
    if (f) { fprintf (f, "cursor-surfaces live=%d (created %d, peak %d) | cursor-sprites live=%d (created %d)\n",
                      live[0], created[0], peak[0], live[1], created[1]); fclose (f); } } return NULL; }
__attribute__((constructor)) static void init (void) {
  if (!getenv ("LP_COUNT_FILE")) return;
  pthread_t th; pthread_create (&th, NULL, loop, NULL); pthread_detach (th); }
