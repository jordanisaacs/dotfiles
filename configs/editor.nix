pkgs: neovimConfiguration: let
  configModule = {
    # Add any custom options (and feel free to upstream them!)
    # options = ...

    config = {
      build.viAlias = false;
      build.vimAlias = true;
      vim.languages = {
        enableLSP = true;
        enableFormat = true;
        enableTreesitter = true;
        enableExtraDiagnostics = true;

        nix.enable = true;
        markdown.enable = true;
        bash.enable = true;
        html.enable = true;
        python.enable = true;
      };
      vim.lsp = {
        formatOnSave = true;

        lightbulb.enable = true;
        lspsaga.enable = false;
        lspkind.enable = true;
        nvimCodeActionMenu.enable = true;
        trouble.enable = true;
        lspSignature.enable = true;
      };

      vim.visuals = {
        enable = true;
        nvimWebDevicons.enable = true;
        indentBlankline = {
          enable = true;
          fillChar = null;
          eolChar = null;
          showCurrContext = true;
        };
      };
      vim.statusline.lualine.enable = true;
      vim.theme = {
        enable = true;
        name = "tokyonight";
        style = "night";
      };
      vim.autopairs.enable = true;
      vim.autocomplete = {
        enable = true;
        type = "nvim-cmp";
      };
      vim.treesitter.context.enable = true;
      vim.keys = {
        enable = true;
        whichKey.enable = true;
      };
      vim.telescope = {
        enable = true;
        fileBrowser = {
          enable = true;
          hijackNetRW = true;
        };
      };
      vim.git = {
        enable = true;
        gitsigns.enable = true;
        gitsigns.codeActions = true;
      };
    };
  };
in {
  dotfiles = neovimConfiguration {
    modules = [configModule];
    inherit pkgs;
  };

  neovimJD = neovimConfiguration {
    modules = [configModule];
    inherit pkgs;
  };
}
