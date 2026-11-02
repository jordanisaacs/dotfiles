// SPDX-License-Identifier: MIT
// Experimental read-only bridge. No process identifiers or termination paths.
#define WLR_USE_UNSTABLE
#include <stdbool.h>
#include <stdlib.h>
#include <time.h>
#include <wayland-server-core.h>
#include <wlr/types/wlr_ext_foreign_toplevel_list_v1.h>
#include <wlr/types/wlr_xdg_shell.h>
#include "health-server.h"

// River resolves this capability while its handle is live. No Window pointer
// crosses the ABI or survives the call; both native lifetimes are observed.
extern struct wlr_xdg_surface *river_health_xdg_surface(
    struct wlr_ext_foreign_toplevel_handle_v1 *handle);

struct manager {
    struct wl_global *global;
    struct wl_event_loop *loop;
    struct wl_list probes;
    struct wl_listener destroy;
};
struct probe {
    struct wl_list link, watches;
    struct manager *manager;
    struct wlr_xdg_client *client;
    struct wl_event_source *timer;
    struct wl_listener timeout;
    bool pending, timed_out;
    uint32_t state;
    int64_t next_probe;
};
struct watch {
    struct wl_resource *resource;
    struct wl_list link;
    struct probe *probe;
    struct wlr_xdg_surface *surface;
    struct wl_listener handle_destroy, surface_destroy;
    bool handle_active, surface_active;
};

static int64_t now_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}
static void set_state(struct probe *probe, uint32_t state) {
    if (state == probe->state) return;
    probe->state = state;
    struct watch *watch;
    wl_list_for_each(watch, &probe->watches, link)
        jd_window_health_watch_v1_send_state(watch->resource, state);
}
static void ping_timeout(struct wl_listener *listener, void *data) {
    (void)data;
    struct probe *probe = wl_container_of(listener, probe, timeout);
    probe->timed_out = true;
    set_state(probe, JD_WINDOW_HEALTH_WATCH_V1_STATE_UNRESPONSIVE);
}
static void attach_timeout(struct probe *probe) {
    struct watch *first = wl_container_of(probe->watches.next, first, link);
    wl_signal_add(&first->surface->events.ping_timeout, &probe->timeout);
}
static int tick(void *data) {
    struct probe *probe = data;
    if (probe->pending && probe->client->ping_serial == 0) {
        // wlroots clears the serial after BOTH pong and timeout. The signal is
        // essential: a serial alone would report a timed-out client healthy.
        if (!probe->timed_out)
            set_state(probe, JD_WINDOW_HEALTH_WATCH_V1_STATE_RESPONSIVE);
        probe->pending = false;
        probe->next_probe = now_ms() + 1000;
    }
    if (!probe->pending && now_ms() >= probe->next_probe) {
        struct watch *first = wl_container_of(probe->watches.next, first, link);
        probe->timed_out = false;
        wlr_xdg_surface_ping(first->surface);
        probe->pending = true;
    }
    wl_event_source_timer_update(probe->timer, 50);
    return 0;
}
static void detach_watch(struct watch *watch) {
    if (watch->handle_active) {
        wl_list_remove(&watch->handle_destroy.link);
        watch->handle_active = false;
    }
    if (watch->surface_active) {
        wl_list_remove(&watch->surface_destroy.link);
        watch->surface_active = false;
    }
    struct probe *probe = watch->probe;
    if (!probe) return;
    wl_list_remove(&probe->timeout.link);
    wl_list_remove(&watch->link);
    watch->probe = NULL;
    watch->surface = NULL;
    if (wl_list_empty(&probe->watches)) {
        wl_event_source_remove(probe->timer);
        wl_list_remove(&probe->link);
        free(probe);
    } else {
        attach_timeout(probe);
    }
}
static void window_closed(struct watch *watch) {
    detach_watch(watch);
    jd_window_health_watch_v1_send_state(watch->resource,
        JD_WINDOW_HEALTH_WATCH_V1_STATE_CLOSED);
}
static void handle_destroy(struct wl_listener *listener, void *data) {
    (void)data;
    struct watch *watch = wl_container_of(listener, watch, handle_destroy);
    window_closed(watch);
}
static void surface_destroy(struct wl_listener *listener, void *data) {
    (void)data;
    struct watch *watch = wl_container_of(listener, watch, surface_destroy);
    window_closed(watch);
}
static void resource_destroy(struct wl_resource *resource) {
    struct watch *watch = wl_resource_get_user_data(resource);
    detach_watch(watch);
    free(watch);
}
static void destroy_request(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}
static const struct jd_window_health_watch_v1_interface watch_impl = {
    .destroy = destroy_request,
};
static void watch_request(struct wl_client *client, struct wl_resource *resource,
        uint32_t id, struct wl_resource *toplevel) {
    struct manager *manager = wl_resource_get_user_data(resource);
    struct wl_resource *object = wl_resource_create(client,
        &jd_window_health_watch_v1_interface, 1, id);
    if (!object) { wl_client_post_no_memory(client); return; }
    struct watch *watch = calloc(1, sizeof(*watch));
    if (!watch) { wl_resource_destroy(object); wl_client_post_no_memory(client); return; }
    watch->resource = object;
    wl_resource_set_implementation(object, &watch_impl, watch, resource_destroy);
    struct wlr_ext_foreign_toplevel_handle_v1 *handle =
        wlr_ext_foreign_toplevel_handle_v1_from_resource(toplevel);
    if (!handle) {
        jd_window_health_watch_v1_send_state(object, JD_WINDOW_HEALTH_WATCH_V1_STATE_CLOSED);
        return;
    }
    watch->handle_destroy.notify = handle_destroy;
    wl_signal_add(&handle->events.destroy, &watch->handle_destroy);
    watch->handle_active = true;
    struct wlr_xdg_surface *surface = river_health_xdg_surface(handle);
    if (!surface) {
        jd_window_health_watch_v1_send_state(object, JD_WINDOW_HEALTH_WATCH_V1_STATE_UNSUPPORTED);
        return;
    }
    struct probe *probe;
    wl_list_for_each(probe, &manager->probes, link)
        if (probe->client == surface->client) goto found;
    probe = calloc(1, sizeof(*probe));
    if (!probe) { wl_client_post_no_memory(client); return; }
    probe->client = surface->client;
    probe->manager = manager;
    probe->state = JD_WINDOW_HEALTH_WATCH_V1_STATE_CHECKING;
    wl_list_init(&probe->watches);
    wl_list_init(&probe->timeout.link);
    probe->timeout.notify = ping_timeout;
    probe->timer = wl_event_loop_add_timer(manager->loop, tick, probe);
    if (!probe->timer) { free(probe); wl_client_post_no_memory(client); return; }
    wl_list_insert(&manager->probes, &probe->link);
found:
    wl_list_remove(&probe->timeout.link);
    watch->probe = probe;
    watch->surface = surface;
    wl_list_insert(&probe->watches, &watch->link);
    watch->surface_destroy.notify = surface_destroy;
    wl_signal_add(&surface->events.destroy, &watch->surface_destroy);
    watch->surface_active = true;
    attach_timeout(probe);
    jd_window_health_watch_v1_send_state(object, probe->state);
    wl_event_source_timer_update(probe->timer, 1);
}
static const struct jd_window_health_manager_v1_interface manager_impl = {
    .destroy = destroy_request,
    .watch = watch_request,
};
static void bind_manager(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *resource = wl_resource_create(client,
        &jd_window_health_manager_v1_interface, version, id);
    if (!resource) { wl_client_post_no_memory(client); return; }
    wl_resource_set_implementation(resource, &manager_impl, data, NULL);
}
static void display_destroy(struct wl_listener *listener, void *data) {
    (void)data;
    struct manager *manager = wl_container_of(listener, manager, destroy);
    // River destroys clients before the display, so their resources have
    // already released all observers and probe timers.
    wl_list_remove(&manager->destroy.link);
    wl_global_destroy(manager->global);
    free(manager);
}
struct wl_global *river_health_create(struct wl_display *display) {
    struct manager *manager = calloc(1, sizeof(*manager));
    if (!manager) return NULL;
    manager->loop = wl_display_get_event_loop(display);
    wl_list_init(&manager->probes);
    manager->global = wl_global_create(display, &jd_window_health_manager_v1_interface,
        1, manager, bind_manager);
    if (!manager->global) { free(manager); return NULL; }
    manager->destroy.notify = display_destroy;
    wl_display_add_destroy_listener(display, &manager->destroy);
    return manager->global;
}
