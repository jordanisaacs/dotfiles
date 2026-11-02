// Exercise layer-shell creation while the compositor's outputs disappear.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>
#include "wlr-layer-shell-client.h"

static struct wl_compositor *compositor;
static struct zwlr_layer_shell_v1 *shell;

static void registry_global(void *data, struct wl_registry *registry,
        uint32_t name, const char *interface, uint32_t version) {
    (void)data;
    if (strcmp(interface, wl_compositor_interface.name) == 0) {
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface,
                version < 4 ? version : 4);
    } else if (strcmp(interface, zwlr_layer_shell_v1_interface.name) == 0) {
        shell = wl_registry_bind(registry, name, &zwlr_layer_shell_v1_interface, 1);
    }
}

static void registry_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data; (void)registry; (void)name;
}

static void configure(void *data, struct zwlr_layer_surface_v1 *surface,
        uint32_t serial, uint32_t width, uint32_t height) {
    (void)data; (void)width; (void)height;
    zwlr_layer_surface_v1_ack_configure(surface, serial);
}

static void closed(void *data, struct zwlr_layer_surface_v1 *surface) {
    (void)data; (void)surface;
}

int main(void) {
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) return 1;
    struct wl_registry *registry = wl_display_get_registry(display);
    const struct wl_registry_listener registry_listener = { registry_global, registry_remove };
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0 || !compositor || !shell) return 2;
    const struct zwlr_layer_surface_v1_listener listener = { configure, closed };
    for (unsigned count = 0; ; count++) {
        struct wl_surface *surface = wl_compositor_create_surface(compositor);
        struct zwlr_layer_surface_v1 *layer = zwlr_layer_shell_v1_get_layer_surface(
                shell, surface, NULL, ZWLR_LAYER_SHELL_V1_LAYER_TOP, "tty-regression");
        zwlr_layer_surface_v1_add_listener(layer, &listener, NULL);
        zwlr_layer_surface_v1_set_size(layer, 80, 40);
        wl_surface_commit(surface);
        if (wl_display_roundtrip(display) < 0) return 3;
        zwlr_layer_surface_v1_destroy(layer);
        wl_surface_destroy(surface);
        if (wl_display_roundtrip(display) < 0) return 4;
        if (count % 100 == 0) {
            printf("created %u layer surfaces\n", count + 1);
            fflush(stdout);
        }
        usleep(2000);
    }
}
