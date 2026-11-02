# Repair only the documentation output. Build tools keep the upstream gawk
# executable and its cache identity.
_final: prev:
let
  # An independent build package set avoids pulling documentation tooling into
  # the bootstrap dependency graph of gawk itself.
  upstream = import prev.path { inherit (prev.stdenv.hostPlatform) system; };
  prepareNotes = upstream.writers.writePython3 "prepare-gawk-notes" { } ''
    from pathlib import Path
    import sys
    import tarfile

    with tarfile.open(sys.argv[1]) as archive:
        member = next(
            item for item in archive.getmembers()
            if item.name.endswith("/doc/gawknotes.texi")
        )
        source = archive.extractfile(member).read().decode("utf-8")
    entry = """@setfilename gawknotes.info
    @dircategory GNU utilities
    @direntry
    * GNU Awk Maintainer Notes: (gawknotes). Maintaining GNU Awk.
    @end direntry
    """
    if "@direntry" not in source:
        source = source.replace("@settitle", entry + "@settitle", 1)
    Path("gawknotes.texi").write_text(source, encoding="utf-8")
  '';
  info =
    upstream.runCommand "gawk-${prev.gawk.version}-info"
      {
        nativeBuildInputs = [ upstream.texinfo ];
      }
      ''
        cp -R ${upstream.gawk.info}/. "$out/"
        chmod -R u+w "$out"
        ${prepareNotes} ${upstream.gawk.src}
        makeinfo --no-split --output="$out/share/info/gawknotes.info" gawknotes.texi
        mkdir index-check
        install-info "$out/share/info/gawknotes.info" index-check/dir
        test -s index-check/dir
      '';
in
{
  gawk = prev.gawk // {
    inherit info;
  };
}
