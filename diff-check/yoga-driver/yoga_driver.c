/* yoga_driver.c -- the C/Yoga side of the layout differential harness.
 *
 * Reads the FROZEN shared spec (diff-check/spec/cases.txt), builds each case's
 * flex tree through the opaque `as_ui_yg_*` seam (u1-prototype/yoga_glue.h) and
 * runs Yoga on it, then prints each node's rectangle in the frozen output
 * format the AS3 driver also prints, so the two outputs can be diffed
 * character-for-character.
 *
 * The spec is the single source of truth for the directives, the ordering
 * rules (an id is globally unique; a `root` line calculates immediately;
 * `check` lines are evaluated at end-of-file) and the expected rectangles. This
 * program adds nothing to it and "fixes" nothing in it: a value that disagrees
 * with Yoga is a FINDING, not something to paper over.
 *
 * Pure C: no Yoga headers here (the seam keeps Yoga opaque). Built against
 * u1-prototype's already-compiled yoga_glue.o + libyoga.a.
 */

#include "yoga_glue.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Tolerance for the per-driver self-test against the spec's expected rects.
 * Same 0.01 as u1-prototype/check-layout.md; it must NOT be widened. */
#define EPS 0.01f

#define MAX_NODES 512
#define MAX_CHECKS 512
#define MAX_ID 128
#define MAX_LINE 1024

typedef struct {
  char id[MAX_ID];
  void* node;
  int childCount; /* number of children inserted so far (insert index) */
} NodeEntry;

typedef struct {
  char name[MAX_ID];
  char id[MAX_ID];
  float l, t, w, h;
} CheckEntry;

static NodeEntry g_nodes[MAX_NODES];
static int g_nodeCount = 0;
static CheckEntry g_checks[MAX_CHECKS];
static int g_checkCount = 0;

/* ------------------------------------------------------------------------- */
/* small helpers                                                             */
/* ------------------------------------------------------------------------- */

/* normalize -0.0f to +0.0f so `%.4f` never prints "-0.0000" (JS toFixed(4)
 * prints "0.0000" for -0, and the AS3 driver uses toFixed). */
static float norm(float v) { return v == 0.0f ? 0.0f : v; }

static int findNode(const char* id) {
  for (int i = 0; i < g_nodeCount; i++) {
    if (strcmp(g_nodes[i].id, id) == 0) return i;
  }
  return -1;
}

static int addNode(const char* id, void* node) {
  if (g_nodeCount >= MAX_NODES) {
    fprintf(stderr, "FATAL: too many nodes (max %d)\n", MAX_NODES);
    exit(2);
  }
  NodeEntry* e = &g_nodes[g_nodeCount];
  snprintf(e->id, MAX_ID, "%s", id);
  e->node = node;
  e->childCount = 0;
  return g_nodeCount++;
}

/* split a line into whitespace-separated tokens, in place */
static int tokenize(char* s, char** out, int max) {
  int n = 0;
  while (*s) {
    while (*s == ' ' || *s == '\t' || *s == '\r' || *s == '\n') s++;
    if (!*s) break;
    if (n >= max) break;
    out[n++] = s;
    while (*s && *s != ' ' && *s != '\t' && *s != '\r' && *s != '\n') s++;
    if (*s) *s++ = 0;
  }
  return n;
}

static int parseAxis(const char* s) {
  return (s[0] == 'w') ? AS_UI_AXIS_WIDTH : AS_UI_AXIS_HEIGHT;
}

static int parseUnit(const char* s) {
  if (strcmp(s, "point") == 0) return AS_UI_UNIT_POINT;
  if (strcmp(s, "percent") == 0) return AS_UI_UNIT_PERCENT;
  if (strcmp(s, "undefined") == 0) return AS_UI_UNIT_UNDEFINED;
  if (strcmp(s, "auto") == 0) return AS_UI_UNIT_AUTO;
  fprintf(stderr, "FATAL: unknown length unit '%s'\n", s);
  exit(2);
}

static int parseEdge(const char* s) {
  if (strcmp(s, "left") == 0) return AS_UI_EDGE_LEFT;
  if (strcmp(s, "top") == 0) return AS_UI_EDGE_TOP;
  if (strcmp(s, "right") == 0) return AS_UI_EDGE_RIGHT;
  if (strcmp(s, "bottom") == 0) return AS_UI_EDGE_BOTTOM;
  if (strcmp(s, "start") == 0) return AS_UI_EDGE_START;
  if (strcmp(s, "end") == 0) return AS_UI_EDGE_END;
  if (strcmp(s, "h") == 0) return AS_UI_EDGE_HORIZONTAL;
  if (strcmp(s, "v") == 0) return AS_UI_EDGE_VERTICAL;
  if (strcmp(s, "all") == 0) return AS_UI_EDGE_ALL;
  fprintf(stderr, "FATAL: unknown edge '%s'\n", s);
  exit(2);
}

/* border only has physical edges plus START/END (no H/V/ALL shorthand is
 * accepted here, to keep the spec honest about what Yoga supports). */
static int parseBorderEdge(const char* s) {
  int e = parseEdge(s);
  if (e == AS_UI_EDGE_HORIZONTAL || e == AS_UI_EDGE_VERTICAL ||
      e == AS_UI_EDGE_ALL) {
    /* Yoga DOES accept the shorthands; keep parseEdge's answer. */
  }
  return e;
}

static int parseDirection(const char* s) {
  if (strcmp(s, "row") == 0) return AS_UI_FLEX_DIR_ROW;
  if (strcmp(s, "column") == 0) return AS_UI_FLEX_DIR_COLUMN;
  if (strcmp(s, "row-reverse") == 0) return AS_UI_FLEX_DIR_ROW_REVERSE;
  if (strcmp(s, "column-reverse") == 0) return AS_UI_FLEX_DIR_COLUMN_REVERSE;
  fprintf(stderr, "FATAL: unknown flex-direction '%s'\n", s);
  exit(2);
}

static int parseWrap(const char* s) {
  if (strcmp(s, "nowrap") == 0) return AS_UI_WRAP_NO_WRAP;
  if (strcmp(s, "wrap") == 0) return AS_UI_WRAP_WRAP;
  if (strcmp(s, "wrap-reverse") == 0) return AS_UI_WRAP_WRAP_REVERSE;
  fprintf(stderr, "FATAL: unknown flex-wrap '%s'\n", s);
  exit(2);
}

/* allow_auto: align-self accepts `auto` (align-items / align-content do not). */
static int parseAlign(const char* s, int allowAuto) {
  if (strcmp(s, "auto") == 0 && allowAuto) return AS_UI_ALIGN_AUTO;
  if (strcmp(s, "flex-start") == 0) return AS_UI_ALIGN_FLEX_START;
  if (strcmp(s, "center") == 0) return AS_UI_ALIGN_CENTER;
  if (strcmp(s, "flex-end") == 0) return AS_UI_ALIGN_FLEX_END;
  if (strcmp(s, "stretch") == 0) return AS_UI_ALIGN_STRETCH;
  if (strcmp(s, "space-between") == 0) return AS_UI_ALIGN_SPACE_BETWEEN;
  if (strcmp(s, "space-around") == 0) return AS_UI_ALIGN_SPACE_AROUND;
  if (strcmp(s, "space-evenly") == 0) return AS_UI_ALIGN_SPACE_EVENLY;
  fprintf(stderr, "FATAL: unknown align '%s'\n", s);
  exit(2);
}

static int parseJustify(const char* s) {
  if (strcmp(s, "flex-start") == 0) return AS_UI_JUSTIFY_FLEX_START;
  if (strcmp(s, "center") == 0) return AS_UI_JUSTIFY_CENTER;
  if (strcmp(s, "flex-end") == 0) return AS_UI_JUSTIFY_FLEX_END;
  if (strcmp(s, "space-between") == 0) return AS_UI_JUSTIFY_SPACE_BETWEEN;
  if (strcmp(s, "space-around") == 0) return AS_UI_JUSTIFY_SPACE_AROUND;
  if (strcmp(s, "space-evenly") == 0) return AS_UI_JUSTIFY_SPACE_EVENLY;
  fprintf(stderr, "FATAL: unknown justify '%s'\n", s);
  exit(2);
}

static int parsePositionType(const char* s) {
  if (strcmp(s, "static") == 0) return AS_UI_POSITION_STATIC;
  if (strcmp(s, "relative") == 0) return AS_UI_POSITION_RELATIVE;
  if (strcmp(s, "absolute") == 0) return AS_UI_POSITION_ABSOLUTE;
  fprintf(stderr, "FATAL: unknown position type '%s'\n", s);
  exit(2);
}

static int parseOverflow(const char* s) {
  if (strcmp(s, "visible") == 0) return AS_UI_OVERFLOW_VISIBLE;
  if (strcmp(s, "hidden") == 0) return AS_UI_OVERFLOW_HIDDEN;
  if (strcmp(s, "scroll") == 0) return AS_UI_OVERFLOW_SCROLL;
  fprintf(stderr, "FATAL: unknown overflow '%s'\n", s);
  exit(2);
}

static int parseDirToken(const char* s) {
  if (strcmp(s, "ltr") == 0) return AS_UI_DIR_LTR;
  if (strcmp(s, "rtl") == 0) return AS_UI_DIR_RTL;
  fprintf(stderr, "FATAL: unknown writing direction '%s'\n", s);
  exit(2);
}

static void* nodeOf(const char* id, int lineNo) {
  int i = findNode(id);
  if (i < 0) {
    fprintf(stderr, "FATAL: line %d: unknown node id '%s'\n", lineNo, id);
    exit(2);
  }
  return g_nodes[i].node;
}

/* ------------------------------------------------------------------------- */
/* spec parsing                                                              */
/* ------------------------------------------------------------------------- */

int main(int argc, char** argv) {
  const char* path = (argc > 1) ? argv[1] : "../spec/cases.txt";
  FILE* fp = fopen(path, "rb");
  if (!fp) {
    fprintf(stderr, "FATAL: cannot open spec '%s'\n", path);
    return 2;
  }

  /* The config nodes are created under. `engine` swaps it; nodes created from
   * that point on use the new one. Configs are kept alive for the whole run. */
  void* cfg = NULL;

  char line[MAX_LINE];
  int lineNo = 0;
  while (fgets(line, sizeof(line), fp)) {
    lineNo++;
    /* '#' starts a comment: drop it and everything after */
    char* hash = strchr(line, '#');
    if (hash) *hash = 0;

    char* tok[24];
    int nt = tokenize(line, tok, 24);
    if (nt == 0) continue;
    const char* d = tok[0];
    if (nt == 1 && strcmp(d, "engine") != 0) {
      fprintf(stderr, "FATAL: line %d: directive '%s' needs arguments\n", lineNo, d);
      return 2;
    }

    if (strcmp(d, "engine") == 0) {
      if (nt < 2) {
        fprintf(stderr, "FATAL: line %d: engine needs web|noweb\n", lineNo);
        return 2;
      }
      int web = (strcmp(tok[1], "web") == 0) ? 1 : 0;
      /* point_scale = 0: no pixel snapping (raw floats), matching the
       * prototype's acceptance口径. use_web_defaults selects row vs column. */
      cfg = as_ui_yg_config_new(0.0f, web);

    } else if (strcmp(d, "node") == 0) {
      if (nt < 3) {
        fprintf(stderr, "FATAL: line %d: node needs <id> <parentId>\n", lineNo);
        return 2;
      }
      const char* id = tok[1];
      const char* parentId = tok[2];
      if (findNode(id) >= 0) {
        fprintf(stderr, "FATAL: line %d: duplicate node id '%s'\n", lineNo, id);
        return 2;
      }
      void* node = as_ui_yg_node_new(cfg);
      int idx = addNode(id, node);
      if (strcmp(parentId, "-1") != 0) {
        int pi = findNode(parentId);
        if (pi < 0) {
          fprintf(stderr, "FATAL: line %d: unknown parent '%s'\n", lineNo, parentId);
          return 2;
        }
        /* children are appended in appearance order */
        as_ui_yg_node_insert(g_nodes[pi].node, node, g_nodes[pi].childCount);
        g_nodes[pi].childCount++;
      }
      (void)idx;

    } else if (strcmp(d, "dir") == 0) {
      /* Deliberately NOT a default: a missing `dir` pins the config default. */
      void* n = nodeOf(tok[1], lineNo);
      as_ui_yg_set_flex_direction(n, parseDirection(tok[2]));

    } else if (strcmp(d, "size") == 0) {
      void* n = nodeOf(tok[1], lineNo);
      as_ui_yg_set_size(n, parseAxis(tok[2]), (float)atof(tok[3]), parseUnit(tok[4]));

    } else if (strcmp(d, "minmax") == 0) {
      void* n = nodeOf(tok[1], lineNo);
      int isMax = (strcmp(tok[3], "max") == 0) ? 1 : 0;
      as_ui_yg_set_minmax(n, parseAxis(tok[2]), isMax, (float)atof(tok[4]),
                          parseUnit(tok[5]));

    } else if (strcmp(d, "pad") == 0) {
      void* n = nodeOf(tok[1], lineNo);
      int unit = (nt >= 5) ? parseUnit(tok[4]) : AS_UI_UNIT_POINT;
      as_ui_yg_set_padding(n, parseEdge(tok[2]), (float)atof(tok[3]), unit);

    } else if (strcmp(d, "border") == 0) {
      void* n = nodeOf(tok[1], lineNo);
      as_ui_yg_set_border(n, parseBorderEdge(tok[2]), (float)atof(tok[3]));

    } else if (strcmp(d, "gap") == 0) {
      void* n = nodeOf(tok[1], lineNo);
      int gutter;
      if (strcmp(tok[2], "row") == 0) gutter = AS_UI_GUTTER_ROW;
      else if (strcmp(tok[2], "col") == 0 || strcmp(tok[2], "column") == 0)
        gutter = AS_UI_GUTTER_COLUMN;
      else if (strcmp(tok[2], "all") == 0) gutter = AS_UI_GUTTER_ALL;
      else {
        fprintf(stderr, "FATAL: line %d: unknown gutter '%s'\n", lineNo, tok[2]);
        return 2;
      }
      int unit = (nt >= 5) ? parseUnit(tok[4]) : AS_UI_UNIT_POINT;
      as_ui_yg_set_gap(n, gutter, (float)atof(tok[3]), unit);

    } else if (strcmp(d, "margin") == 0) {
      void* n = nodeOf(tok[1], lineNo);
      int unit = (nt >= 5) ? parseUnit(tok[4]) : AS_UI_UNIT_POINT;
      as_ui_yg_set_margin(n, parseEdge(tok[2]), (float)atof(tok[3]), unit);

    } else if (strcmp(d, "inset") == 0) {
      void* n = nodeOf(tok[1], lineNo);
      int unit = (nt >= 5) ? parseUnit(tok[4]) : AS_UI_UNIT_POINT;
      as_ui_yg_set_position(n, parseEdge(tok[2]), (float)atof(tok[3]), unit);

    } else if (strcmp(d, "pos") == 0) {
      void* n = nodeOf(tok[1], lineNo);
      as_ui_yg_set_position_type(n, parsePositionType(tok[2]));

    } else if (strcmp(d, "overflow") == 0) {
      void* n = nodeOf(tok[1], lineNo);
      as_ui_yg_set_overflow(n, parseOverflow(tok[2]));

    } else if (strcmp(d, "wrap") == 0) {
      void* n = nodeOf(tok[1], lineNo);
      as_ui_yg_set_flex_wrap(n, parseWrap(tok[2]));

    } else if (strcmp(d, "justify") == 0) {
      void* n = nodeOf(tok[1], lineNo);
      as_ui_yg_set_justify(n, parseJustify(tok[2]));

    } else if (strcmp(d, "align") == 0) {
      void* n = nodeOf(tok[1], lineNo);
      as_ui_yg_set_align_items(n, parseAlign(tok[2], 0));

    } else if (strcmp(d, "alignself") == 0) {
      void* n = nodeOf(tok[1], lineNo);
      as_ui_yg_set_align_self(n, parseAlign(tok[2], 1));

    } else if (strcmp(d, "aligncontent") == 0) {
      void* n = nodeOf(tok[1], lineNo);
      as_ui_yg_set_align_content(n, parseAlign(tok[2], 0));

    } else if (strcmp(d, "flex") == 0) {
      void* n = nodeOf(tok[1], lineNo);
      as_ui_yg_set_flex(n, (float)atof(tok[2]), (float)atof(tok[3]),
                        (float)atof(tok[4]), parseUnit(tok[5]));

    } else if (strcmp(d, "boxsizing") == 0) {
      void* n = nodeOf(tok[1], lineNo);
      int bs = (strcmp(tok[2], "content") == 0) ? AS_UI_BOX_SIZING_CONTENT_BOX
                                                : AS_UI_BOX_SIZING_BORDER_BOX;
      as_ui_yg_set_box_sizing(n, bs);

    } else if (strcmp(d, "root") == 0) {
      if (nt < 4) {
        fprintf(stderr, "FATAL: line %d: root needs <id> <availW> <availH>\n", lineNo);
        return 2;
      }
      void* n = nodeOf(tok[1], lineNo);
      int dir = (nt >= 5) ? parseDirToken(tok[4]) : AS_UI_DIR_LTR;
      as_ui_yg_calculate(n, (float)atof(tok[2]), (float)atof(tok[3]), dir);

    } else if (strcmp(d, "check") == 0) {
      /* Only queued here; evaluated at end-of-file (see the spec header). */
      if (nt < 7) {
        fprintf(stderr, "FATAL: line %d: check needs <name> <id> l t w h\n", lineNo);
        return 2;
      }
      if (g_checkCount >= MAX_CHECKS) {
        fprintf(stderr, "FATAL: too many checks (max %d)\n", MAX_CHECKS);
        return 2;
      }
      CheckEntry* c = &g_checks[g_checkCount++];
      snprintf(c->name, MAX_ID, "%s", tok[1]);
      snprintf(c->id, MAX_ID, "%s", tok[2]);
      c->l = (float)atof(tok[3]);
      c->t = (float)atof(tok[4]);
      c->w = (float)atof(tok[5]);
      c->h = (float)atof(tok[6]);

    } else {
      fprintf(stderr, "FATAL: line %d: unknown directive '%s'\n", lineNo, d);
      return 2;
    }
  }
  fclose(fp);

  /* ------------------------------------------------------------------ */
  /* print every GOT line, in spec order                                */
  /* ------------------------------------------------------------------ */
  float rects[MAX_CHECKS][4];
  for (int i = 0; i < g_checkCount; i++) {
    void* n = nodeOf(g_checks[i].id, 0);
    float r[4];
    as_ui_yg_layout_get(n, r);
    for (int k = 0; k < 4; k++) rects[i][k] = norm(r[k]);
    printf("GOT %s %.4f %.4f %.4f %.4f\n", g_checks[i].name, rects[i][0],
           rects[i][1], rects[i][2], rects[i][3]);
  }

  /* ------------------------------------------------------------------ */
  /* human-readable self-test against the spec's expected rectangles     */
  /* ------------------------------------------------------------------ */
  int failures = 0;
  for (int i = 0; i < g_checkCount; i++) {
    const CheckEntry* c = &g_checks[i];
    const float* r = rects[i];
    int ok = fabsf(r[0] - c->l) <= EPS && fabsf(r[1] - c->t) <= EPS &&
             fabsf(r[2] - c->w) <= EPS && fabsf(r[3] - c->h) <= EPS;
    if (ok) {
      printf("  OK   %s got(%.4f,%.4f,%.4f,%.4f) want(%.4f,%.4f,%.4f,%.4f)\n",
             c->name, r[0], r[1], r[2], r[3], c->l, c->t, c->w, c->h);
    } else {
      failures++;
      printf("  FAIL %s got(%.4f,%.4f,%.4f,%.4f) want(%.4f,%.4f,%.4f,%.4f)\n",
             c->name, r[0], r[1], r[2], r[3], c->l, c->t, c->w, c->h);
    }
  }

  printf("---- %d checks, %d failures ----\n", g_checkCount, failures);
  return failures == 0 ? 0 : 1;
}
