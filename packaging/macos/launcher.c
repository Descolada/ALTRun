// Keep ALTRun's bundle identity while replacing this process with its bundled Keysharp host.
#include <errno.h>
#include <mach-o/dyld.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void fail(const char *message) {
    fprintf(stderr, "ALTRun: %s: %s\n", message, strerror(errno));
    exit(1);
}

int main(int argc, char **argv) {
    uint32_t size = 0;
    _NSGetExecutablePath(NULL, &size);
    char *raw = malloc(size);
    char executable[PATH_MAX], bundle[PATH_MAX], host[PATH_MAX], source[PATH_MAX], runtime[PATH_MAX];
    if (!raw || _NSGetExecutablePath(raw, &size) || !realpath(raw, executable)) fail("cannot locate app bundle");
    free(raw);
    snprintf(bundle, sizeof(bundle), "%s", executable);
    for (int index = 0; index < 3; index++) {
        char *separator = strrchr(bundle, '/');
        if (!separator) { errno = EINVAL; fail("invalid app bundle layout"); }
        *separator = '\0';
    }
    if (snprintf(host, sizeof(host), "%s/Contents/MacOS/Keysharp", bundle) >= (int)sizeof(host)
        || snprintf(source, sizeof(source), "%s/Contents/Resources/ALTRun", bundle) >= (int)sizeof(source)
        || snprintf(runtime, sizeof(runtime), "%s/Contents/Resources/dotnet", bundle) >= (int)sizeof(runtime)) {
        errno = ENAMETOOLONG; fail("app bundle path is too long");
    }
    setenv("ALTRUN_APP_BUNDLE", bundle, 1);
    setenv("ALTRUN_SOURCE_DIR", source, 1);
    setenv("DOTNET_ROOT", runtime, 1);
#if defined(__arm64__)
    setenv("DOTNET_ROOT_ARM64", runtime, 1);
#else
    setenv("DOTNET_ROOT_X64", runtime, 1);
#endif
    setenv("DOTNET_MULTILEVEL_LOOKUP", "0", 1);
    if (chdir(source)) fail("cannot open bundled source folder");

    // A diagnostics entry point also permits isolated source/child-script checks without starting ALTRun.
    int direct = argc > 1 && strcmp(argv[1], "--keysharp") == 0;
    char **arguments = calloc((size_t)argc + 4, sizeof(char *));
    if (!arguments) fail("cannot prepare arguments");
    int next = 0;
    arguments[next++] = host;
    arguments[next++] = "--errorstdout";
    if (!direct) arguments[next++] = "ALTRun.ahk";
    for (int index = direct ? 2 : 1; index < argc; index++) arguments[next++] = argv[index];
    execv(host, arguments);
    fail("cannot run bundled Keysharp");
    return 1;
}
