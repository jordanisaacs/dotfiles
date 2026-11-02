{ editor, system }:
let
  # The editor's nested Lisp lock still points pm at its author's worktree.
  # Override the source while Twist computes package metadata: overrideAttrs
  # happens too late, after Twist has already inspected the missing checkout.
  twist = editor.inputs.twist;
  fixedInputs = editor.inputs // {
    self = editor;
    twist = twist // {
      lib = twist.lib // {
        makeEnv =
          args:
          twist.lib.makeEnv (
            args
            // {
              inputOverrides = (args.inputOverrides or { }) // {
                pm = _: _: { src = editor.inputs.pm-src; };
              };
            }
          );
      };
    };
  };
  fixedEditor = (import (editor + "/flake.nix")).outputs fixedInputs;
in
fixedEditor.packages.${system}.emacs-jd
