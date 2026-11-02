pkgs: neovimConfiguration:
let
  configModule = {
    # Add any custom options (and feel free to upstream them!)
    # options = ...

    config = {
      build.viAlias = false;
      build.vimAlias = true;
      vim = {
        languages = {
          enableLSP = true;
          enableFormat = true;
          enableTreesitter = true;
          enableExtraDiagnostics = true;

          nix.enable = true;
          nix.format.type = "nixpkgs-fmt";
          markdown.enable = true;
          bash.enable = true;
          html.enable = true;
          python.enable = true;
          clang.enable = true;
        };

        lsp = {
          formatOnSave = true;

          lightbulb.enable = true;
          lspsaga.enable = false;
          lspkind.enable = true;
          nvimCodeActionMenu.enable = true;
          trouble.enable = true;
          lspSignature.enable = true;
        };

        visuals = {
          enable = true;
          nvimWebDevicons.enable = true;
          indentBlankline = {
            enable = true;
            fillChar = null;
            eolChar = null;
            showCurrContext = true;
          };
        };

        statusline.lualine.enable = true;

        theme = {
          enable = true;
          name = "tokyonight";
          style = "night";
        };

        autopairs.enable = true;

        autocomplete = {
          enable = true;
          type = "nvim-cmp";
        };

        treesitter = {
          context.enable = true;
          fold = true;
        };

        keys = {
          enable = true;
          whichKey.enable = true;
        };

        telescope = {
          enable = true;
          fileBrowser = {
            enable = true;
            hijackNetRW = true;
          };
        };

        git = {
          enable = true;
          gitsigns.enable = true;
          gitsigns.codeActions = true;
        };
      };
    };
  };
in
{
  dotfiles = neovimConfiguration {
    modules = [ configModule ];
    inherit pkgs;
  };

  neovimJD = neovimConfiguration {
    modules = [ configModule ];
    inherit pkgs;
  };
}
