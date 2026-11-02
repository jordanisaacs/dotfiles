# UAPI ELF dlopen notes list alternative sonames for one library. Keep those
# alternatives grouped when collecting initrd dependencies, rather than
# requiring every supported ABI version simultaneously.
_final: prev: {
  makeInitrdNGTool = prev.makeInitrdNGTool.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./initrd-dlopen.patch ];
  });
}
