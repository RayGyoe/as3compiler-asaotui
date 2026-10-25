/* emcc-launcher.c -- a Windows stand-in for the emsdk's POSIX `emcc` wrapper.
 *
 * WHY THIS EXISTS
 * ---------------
 * `as-aot --target wasm --package web` spawns `$EMSDK_HOME/upstream/emscripten/emcc`
 * DIRECTLY, with no shell (src/build.ts: emccPath + spawnSync). On the emsdk the
 * file at that path is a `#!/bin/sh` wrapper, and Windows cannot CreateProcess a
 * shell script: the spawn fails with ENOENT/EINVAL before a single flag is read
 * ("cannot build for --package web: emcc not found: .../emcc"). The Windows entry
 * point the SDK ships is `emcc.bat`, which needs cmd.exe.
 *
 * So this launcher is a PE binary named `emcc`, installed at
 * `<shim>/upstream/emscripten/emcc` (Windows even appends `.exe` when the name has
 * no extension, so `emcc.exe` in that directory is found too). It re-creates the
 * environment the driver deliberately throws away -- the compiler passes
 * `env = { PATH: ... }`, i.e. ONLY PATH, built with POSIX ':' separators that a
 * Windows PATH cannot parse -- and hands the arguments to `emcc.bat`.
 *
 * Configuration is a 4-line text file NEXT TO THIS EXE (see ui-demo/web-gallery.cjs,
 * which writes it), so the launcher itself is path-independent and needs no
 * recompilation when the SDK moves:
 *
 *     line 1  EM_CONFIG     <sdk>/.emscripten
 *     line 2  EMSDK_PYTHON  <sdk>/python/<ver>/python.exe
 *     line 3  emcc.bat      <sdk>/upstream/emscripten/emcc.bat
 *     line 4  PATH          the dirs emcc and its children need, ';'-separated
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LINELEN 4096
#define CMDLEN  65536

static int readLine(FILE *f, char *buf, int n) {
  if (!fgets(buf, n, f)) { buf[0] = 0; return 0; }
  int len = (int)strlen(buf);
  while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r' || buf[len - 1] == ' ')) {
    buf[--len] = 0;
  }
  return 1;
}

/* Quote one argument for cmd.exe: wrap in double quotes, double any inner quote.
 * The SDK's own flag set (-c, -O2, -Iname, -o name, -s KEY=VAL, -Dname=val) never
 * contains a quote or a cmd metacharacter, but a path with a space is normal. */
static void appendArg(char *out, size_t cap, const char *arg) {
  size_t used = strlen(out);
  if (used + 3 >= cap) return;
  out[used++] = ' ';
  out[used++] = '"';
  for (const char *p = arg; *p && used + 3 < cap; p++) {
    if (*p == '"') out[used++] = '\\';
    out[used++] = *p;
  }
  out[used++] = '"';
  out[used] = 0;
}

int main(int argc, char **argv) {
  char self[MAX_PATH];
  if (!GetModuleFileNameA(NULL, self, MAX_PATH)) {
    fprintf(stderr, "emcc-launcher: cannot resolve my own path\n");
    return 3;
  }
  char *slash = strrchr(self, '\\');
  if (slash) *slash = 0;

  char conf[MAX_PATH + 64];
  snprintf(conf, sizeof(conf), "%s\\emcc-launcher.txt", self);

  char cfg[4][LINELEN];
  FILE *f = fopen(conf, "r");
  if (!f) {
    fprintf(stderr, "emcc-launcher: missing config %s\n", conf);
    return 3;
  }
  for (int i = 0; i < 4; i++) readLine(f, cfg[i], LINELEN);
  fclose(f);

  if (!cfg[2][0]) {
    fprintf(stderr, "emcc-launcher: %s line 3 must name emcc.bat\n", conf);
    return 3;
  }

  if (cfg[0][0]) SetEnvironmentVariableA("EM_CONFIG", cfg[0]);
  if (cfg[1][0]) SetEnvironmentVariableA("EMSDK_PYTHON", cfg[1]);
  if (cfg[3][0]) SetEnvironmentVariableA("PATH", cfg[3]);

  char *line = (char *)calloc(CMDLEN, 1);
  if (!line) return 3;
  /* `cmd /c "<bat>" <args>`: cmd strips the first and last quote of the command
   * when it starts with one, so the bat path is wrapped in its own quotes and the
   * whole command in another pair. */
  snprintf(line, CMDLEN, "/c \"\"%s\"", cfg[2]);
  for (int i = 1; i < argc; i++) appendArg(line, CMDLEN, argv[i]);
  strncat(line, "\"", CMDLEN - strlen(line) - 1);

  char cmdExe[MAX_PATH];
  DWORD n = GetEnvironmentVariableA("COMSPEC", cmdExe, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) strcpy(cmdExe, "C:\\Windows\\System32\\cmd.exe");

  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  memset(&si, 0, sizeof(si));
  si.cb = sizeof(si);
  memset(&pi, 0, sizeof(pi));

  if (!CreateProcessA(cmdExe, line, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi)) {
    fprintf(stderr, "emcc-launcher: CreateProcess failed (%lu): %s\n",
            (unsigned long)GetLastError(), line);
    free(line);
    return 3;
  }
  WaitForSingleObject(pi.hProcess, INFINITE);
  DWORD code = 1;
  GetExitCodeProcess(pi.hProcess, &code);
  CloseHandle(pi.hProcess);
  CloseHandle(pi.hThread);
  free(line);
  return (int)code;
}