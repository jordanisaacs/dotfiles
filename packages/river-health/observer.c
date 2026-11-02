// SPDX-License-Identifier: MIT
#define _POSIX_C_SOURCE 200809L
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>
#include "health-client.h"
#include "foreign-client.h"

static struct jd_window_health_manager_v1 *manager;
static struct ext_foreign_toplevel_list_v1 *inventory;
static uint32_t manager_name, inventory_name;
static bool unavailable;
static struct wl_list entries;

struct entry {
    struct wl_list link;
    struct ext_foreign_toplevel_handle_v1 *handle;
    struct jd_window_health_watch_v1 *watch;
    char *id, *app_id;
};

static void json_string(const char *value) {
    putchar('"');
    for (const unsigned char *c = (const unsigned char *)(value ? value : ""); *c; c++) {
        if (*c == '"' || *c == '\\') printf("\\%c", *c);
        else if (*c < 32) printf("\\u%04x", *c);
        else putchar(*c);
    }
    putchar('"');
}

static void report(struct entry *entry, uint32_t value) {
    const char *status = value == 1 ? "responsive" : value == 2 ? "unresponsive" :
        value == 4 ? "closed" : "unknown";
    printf("{\"identifier\":"); json_string(entry->id);
    printf(",\"app_id\":"); json_string(entry->app_id);
    printf(",\"status\":"); json_string(status);
    printf(",\"native_state\":%u}\n", value);
    fflush(stdout);
}

static void release(struct entry *entry) {
    if (entry->watch) jd_window_health_watch_v1_destroy(entry->watch);
    if (entry->handle) ext_foreign_toplevel_handle_v1_destroy(entry->handle);
    wl_list_remove(&entry->link);
    free(entry->id);
    free(entry->app_id);
    free(entry);
}

static void state(void *data, struct jd_window_health_watch_v1 *watch, uint32_t value) {
    (void)watch;
    struct entry *entry = data;
    report(entry, value);
    if (value == JD_WINDOW_HEALTH_WATCH_V1_STATE_CLOSED) release(entry);
}
static const struct jd_window_health_watch_v1_listener health_listener = { .state = state };

static void closed(void *data, struct ext_foreign_toplevel_handle_v1 *handle) {
    (void)handle;
    struct entry *entry = data;
    // Either native lifetime event may arrive first. Emit once and destroy both
    // proxies; libwayland discards queued events for destroyed proxy objects.
    report(entry, JD_WINDOW_HEALTH_WATCH_V1_STATE_CLOSED);
    release(entry);
}
static void done(void *data, struct ext_foreign_toplevel_handle_v1 *handle) {
    struct entry *entry = data;
    if (!entry->watch && manager && entry->id) {
        entry->watch = jd_window_health_manager_v1_watch(manager, handle);
        if (!entry->watch) { unavailable = true; return; }
        jd_window_health_watch_v1_add_listener(entry->watch, &health_listener, entry);
    }
}
static void title(void *data, struct ext_foreign_toplevel_handle_v1 *handle, const char *value) {
    (void)data; (void)handle; (void)value;
}
static void app_id(void *data, struct ext_foreign_toplevel_handle_v1 *handle, const char *value) {
    (void)handle;
    struct entry *entry = data;
    free(entry->app_id); entry->app_id = strdup(value);
    if (!entry->app_id) unavailable = true;
}
static void identifier(void *data, struct ext_foreign_toplevel_handle_v1 *handle, const char *value) {
    (void)handle;
    struct entry *entry = data;
    free(entry->id); entry->id = strdup(value);
    if (!entry->id) unavailable = true;
}
static const struct ext_foreign_toplevel_handle_v1_listener entry_listener = {
    .closed = closed, .done = done, .title = title, .app_id = app_id, .identifier = identifier,
};
static void toplevel(void *data, struct ext_foreign_toplevel_list_v1 *list,
        struct ext_foreign_toplevel_handle_v1 *handle) {
    (void)data; (void)list;
    struct entry *entry = calloc(1, sizeof(*entry));
    if (!entry) { unavailable = true; return; }
    entry->handle = handle;
    wl_list_insert(&entries, &entry->link);
    ext_foreign_toplevel_handle_v1_add_listener(handle, &entry_listener, entry);
}
static void finished(void *data, struct ext_foreign_toplevel_list_v1 *list) {
    (void)data; (void)list;
    unavailable = true;
}
static const struct ext_foreign_toplevel_list_v1_listener list_listener = {
    .toplevel = toplevel, .finished = finished,
};
static void global(void *data, struct wl_registry *registry, uint32_t name,
        const char *interface, uint32_t version) {
    (void)data; (void)version;
    if (!strcmp(interface, "jd_window_health_manager_v1")) {
        manager = wl_registry_bind(registry, name, &jd_window_health_manager_v1_interface, 1);
        manager_name = name;
    } else if (!strcmp(interface, "ext_foreign_toplevel_list_v1")) {
        inventory = wl_registry_bind(registry, name, &ext_foreign_toplevel_list_v1_interface, 1);
        inventory_name = name;
        ext_foreign_toplevel_list_v1_add_listener(inventory, &list_listener, NULL);
    }
}
static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data; (void)registry;
    if (name == manager_name || name == inventory_name) unavailable = true;
}
static const struct wl_registry_listener registry_listener = { global, global_remove };

int main(int argc, char **argv) {
    if (argc != 2 || strcmp(argv[1], "--watch")) {
        fputs("Usage: river-health --watch\n", stderr);
        return 2;
    }
    wl_list_init(&entries);
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) return 1;
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    int result = wl_display_roundtrip(display);
    if (result >= 0 && (!manager || !inventory || unavailable)) {
        unavailable = true;
        fputs("Native app health API unavailable; use Waiting for app.\n", stderr);
    }
    if (result >= 0 && !unavailable) {
        while (!unavailable && (result = wl_display_dispatch(display)) >= 0) {}
    }
    struct entry *entry, *tmp;
    wl_list_for_each_safe(entry, tmp, &entries, link) release(entry);
    if (inventory) ext_foreign_toplevel_list_v1_destroy(inventory);
    if (manager) jd_window_health_manager_v1_destroy(manager);
    wl_registry_destroy(registry);
    wl_display_disconnect(display);
    return unavailable ? 3 : 1;
}
