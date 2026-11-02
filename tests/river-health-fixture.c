// SPDX-License-Identifier: MIT
#define _GNU_SOURCE
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <wayland-client.h>
#include "xdg-client.h"
#include "security-client.h"

static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct xdg_wm_base *shell;
static int fixture;
static int sandbox_check;
static bool sandbox_has_health, sandbox_has_inventory, sandbox_has_shell;
static struct wp_security_context_manager_v1 *security_manager;
static volatile sig_atomic_t close_one;
static void ping(void *data, struct xdg_wm_base *base, uint32_t serial) {
    (void)data;
    puts("ping"); fflush(stdout);
    xdg_wm_base_pong(base, serial);
}
static const struct xdg_wm_base_listener shell_listener = { .ping = ping };
static void global(void *data, struct wl_registry *registry, uint32_t name,
        const char *interface, uint32_t version) {
    (void)data; (void)version;
    if (sandbox_check == 2) {
        if (!strcmp(interface, "jd_window_health_manager_v1")) sandbox_has_health = true;
        if (!strcmp(interface, "ext_foreign_toplevel_list_v1")) sandbox_has_inventory = true;
        if (!strcmp(interface, "xdg_wm_base")) sandbox_has_shell = true;
    } else if (sandbox_check == 1) {
        if (!strcmp(interface, "wp_security_context_manager_v1"))
            security_manager = wl_registry_bind(registry, name,
                &wp_security_context_manager_v1_interface, 1);
    } else if (fixture) {
        if (!strcmp(interface, "wl_compositor"))
            compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
        else if (!strcmp(interface, "wl_shm"))
            shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
        else if (!strcmp(interface, "xdg_wm_base")) {
            shell = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
            xdg_wm_base_add_listener(shell, &shell_listener, NULL);
        }
    }
}
static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data; (void)registry; (void)name;
}
static const struct wl_registry_listener registry_listener = { global, global_remove };
struct window {
    struct wl_surface *surface;
    struct xdg_surface *xdg;
    struct xdg_toplevel *top;
    struct wl_buffer *buffer;
};
static void configure(void *data, struct xdg_surface *surface, uint32_t serial) {
    struct window *window = data;
    xdg_surface_ack_configure(surface, serial);
    wl_surface_attach(window->surface, window->buffer, 0, 0);
    wl_surface_damage(window->surface, 0, 0, 64, 64);
    wl_surface_commit(window->surface);
}
static const struct xdg_surface_listener surface_listener = { configure };
static void top_configure(void *data, struct xdg_toplevel *top,
        int32_t width, int32_t height, struct wl_array *states) {
    (void)data; (void)top; (void)width; (void)height; (void)states;
}
static void close_veto(void *data, struct xdg_toplevel *top) {
    (void)data; (void)top;
    puts("close-vetoed"); fflush(stdout);
}
static const struct xdg_toplevel_listener top_listener = {
    .configure = top_configure, .close = close_veto,
};
static void drop_one(int sig) { (void)sig; close_one = 1; }
static int check_security_context(struct wl_display *outer) {
    if (!security_manager) return 2;
    struct sockaddr_un address = { .sun_family = AF_UNIX };
    int length = snprintf(address.sun_path, sizeof(address.sun_path), "%s/health-sandbox",
        getenv("XDG_RUNTIME_DIR"));
    if (length < 0 || (size_t)length >= sizeof(address.sun_path)) return 2;
    int listener = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    int lifetime[2];
    if (listener < 0 || pipe(lifetime) < 0 ||
            bind(listener, (struct sockaddr *)&address, sizeof(address)) < 0 ||
            listen(listener, 4) < 0) return 2;
    struct wp_security_context_v1 *context =
        wp_security_context_manager_v1_create_listener(security_manager, listener, lifetime[0]);
    wp_security_context_v1_set_sandbox_engine(context, "native-health-test");
    wp_security_context_v1_set_app_id(context, "health-test-sandbox");
    wp_security_context_v1_commit(context);
    if (wl_display_roundtrip(outer) < 0) return 2;
    sandbox_check = 2;
    struct wl_display *inner = wl_display_connect(address.sun_path);
    if (!inner) return 2;
    struct wl_registry *registry = wl_display_get_registry(inner);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(inner) < 0) return 2;
    bool passed = sandbox_has_shell && !sandbox_has_health && !sandbox_has_inventory;
    wl_display_disconnect(inner);
    wp_security_context_v1_destroy(context);
    wl_display_roundtrip(outer);
    close(listener); close(lifetime[0]); close(lifetime[1]);
    unlink(address.sun_path);
    if (passed) puts("sandbox-context-filtered");
    return passed ? 0 : 2;
}
int main(int argc, char **argv) {
    fixture = argc >= 2 && !strcmp(argv[1], "--fixture");
    sandbox_check = argc >= 2 && !strcmp(argv[1], "--sandbox-check");
    if (!fixture && !sandbox_check) return 2;
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) return 1;
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0) return 1;
    if (sandbox_check) return check_security_context(display);
    if (!compositor || !shm || !shell || argc != 3) return 2;
    int fd = memfd_create("health-fixture", 0);
    if (fd < 0 || ftruncate(fd, 64 * 64 * 4) < 0) return 2;
    void *pixels = mmap(NULL, 64 * 64 * 4, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (pixels == MAP_FAILED) return 2;
    memset(pixels, 0x88, 64 * 64 * 4);
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, 64 * 64 * 4);
    struct window windows[2] = {0};
    for (int i = 0; i < 2; ++i) {
        struct window *w = &windows[i];
        w->buffer = wl_shm_pool_create_buffer(pool, 0, 64, 64, 64 * 4, WL_SHM_FORMAT_XRGB8888);
        w->surface = wl_compositor_create_surface(compositor);
        w->xdg = xdg_wm_base_get_xdg_surface(shell, w->surface);
        xdg_surface_add_listener(w->xdg, &surface_listener, w);
        w->top = xdg_surface_get_toplevel(w->xdg);
        xdg_toplevel_add_listener(w->top, &top_listener, w);
        xdg_toplevel_set_app_id(w->top, argv[2]);
        xdg_toplevel_set_title(w->top, argv[2]);
        wl_surface_commit(w->surface);
    }
    signal(SIGUSR1, drop_one);
    while (true) {
        if (close_one && windows[0].top) {
            xdg_toplevel_destroy(windows[0].top);
            xdg_surface_destroy(windows[0].xdg);
            wl_surface_destroy(windows[0].surface);
            windows[0].top = NULL;
        }
        while (wl_display_prepare_read(display) != 0)
            if (wl_display_dispatch_pending(display) < 0) return 1;
        wl_display_flush(display);
        struct pollfd p = { wl_display_get_fd(display), POLLIN, 0 };
        int ready = poll(&p, 1, 100);
        if (ready > 0) {
            if (wl_display_read_events(display) < 0) return 1;
        } else wl_display_cancel_read(display);
        if (wl_display_dispatch_pending(display) < 0) return 1;
    }
}
