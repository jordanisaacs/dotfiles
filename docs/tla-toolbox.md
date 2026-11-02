# TLA+ Toolbox compatibility

The packaged Toolbox uses an older SWT/Eclipse runtime. Its application-local
launcher selects Xwayland to avoid fractional-scale widget clipping. The overlay
repairs SWT's MIME database location so native desktop default-browser discovery
works on NixOS; Firefox is selected by MIME policy rather than hardcoded there.

The package checks the expected Java constant before modifying its JAR. Revisit
both compatibility adjustments when updating Toolbox's bundled runtime. Workspace
and explicit `-data` / `-configuration` arguments remain launcher inputs.

`tla-toolbox` launches the actual app at fractional scale in a private VM,
measures widget/font geometry and invokes its external-browser API against a
private MIME handler. An unmodified-package control must reproduce the failure;
the test does not alter user workspaces or visit external sites.
