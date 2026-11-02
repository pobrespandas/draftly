// CI-only diagnostics. Preserve each termination function and its status.
#include <execinfo.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int is_test_process(void) {
    const char *name = getprogname();
    return name && (strcmp(name, "DraftlyPackageTests") == 0 ||
                    strcmp(name, "swiftpm-testing-helper") == 0 ||
                    strcmp(name, "DraftlyTests") == 0);
}

static void trace(const char *function, int status) {
    if (!is_test_process()) return;
    void *frames[48];
    int count = backtrace(frames, 48);
    dprintf(STDERR_FILENO, "\nDRAFTLY_TEST_TERMINATION process=%s function=%s status=%d pid=%d\n",
            getprogname(), function, status, getpid());
    backtrace_symbols_fd(frames, count, STDERR_FILENO);
}

__attribute__((constructor)) static void trace_loaded(void) {
    if (is_test_process())
        dprintf(STDERR_FILENO, "DRAFTLY_TEST_TRACE_LOADED process=%s pid=%d\n", getprogname(), getpid());
}

__attribute__((noreturn)) static void traced_exit(int status) {
    trace("exit", status);
    exit(status);
    __builtin_unreachable();
}

__attribute__((noreturn)) static void traced_immediate_exit(int status) {
    trace("_exit", status);
    _exit(status);
    __builtin_unreachable();
}

#define INTERPOSE(replacement, original) \
    __attribute__((used)) static struct { const void *new_function; const void *old_function; } \
    binding_##original __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)(unsigned long)&replacement, (const void *)(unsigned long)&original \
    }

INTERPOSE(traced_exit, exit);
INTERPOSE(traced_immediate_exit, _exit);
