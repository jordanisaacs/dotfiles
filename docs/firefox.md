# Firefox configuration

The Firefox Home Manager module owns package selection, profiles, default-browser
associations, privacy preferences, AI feature policies and extension installation.
Use upstream preferences/policies where available. UI font, output scale and
profile-specific zoom are separate settings; avoid compensating with monospace
fonts or unrelated global scale changes.

Vertical tabs use the browser's sidebar with compact hover expansion. The user
style should preserve tab geometry between collapsed and expanded states. Profile
controls and other chrome preferences are configured in the same module.

Extensions use explicit package/policy declarations. The BPC package is a pinned,
signed upstream archive with automatic extension updates disabled; review source,
permissions and network behavior again when changing its hash/version. Preserve
Firefox signature verification. An earlier source review does not establish the
safety of a later release or optional remotely fetched rules.
