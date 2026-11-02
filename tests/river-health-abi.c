#define WLR_USE_UNSTABLE
#include <stddef.h>
#include <stdint.h>
#include <wlr/types/wlr_ext_foreign_toplevel_list_v1.h>
#include <wlr/types/wlr_xdg_shell.h>

uint64_t river_health_c_abi(unsigned index) {
    const uint64_t fields[] = {
        sizeof(struct wlr_xdg_surface),
        offsetof(struct wlr_xdg_surface, events),
        offsetof(struct wlr_xdg_surface, client),
        offsetof(struct wlr_xdg_surface, role_resource),
        sizeof(struct wlr_xdg_client),
        offsetof(struct wlr_xdg_client, ping_serial),
        sizeof(struct wlr_xdg_toplevel),
        offsetof(struct wlr_xdg_toplevel, base),
        sizeof(struct wlr_ext_foreign_toplevel_handle_v1),
        offsetof(struct wlr_ext_foreign_toplevel_handle_v1, data),
        offsetof(struct wlr_ext_foreign_toplevel_handle_v1, events),
    };
    return fields[index];
}
