final: previous: {
  libreoffice = previous.libreoffice.overrideAttrs (old: {
    # Some releases already ship unversioned desktop-entry commands. Rewriting
    # the older versioned form is optional, and needs no missing-match warning.
    buildCommand =
      final.lib.replaceStrings
        [ ''--replace "Exec=libreoffice'' ]
        [
          ''--replace-quiet "Exec=libreoffice''
        ]
        old.buildCommand;
  });
}
