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
        html.enable = true;
        sql = {
          enable = true;
          lsp.enable = false;
        };
        python.enable = true;
      };
      vim.lsp = {
        formatOnSave = true;

        lightbulb.enable = true;
        lspsaga.enable = false;
        nvimCodeActionMenu.enable = true;
        trouble.enable = true;
        lspSignature.enable = true;
      };
      vim.visuals = {
        enable = true;
        nvimWebDevicons.enable = true;
        lspkind.enable = true;
        indentBlankline = {
          enable = true;
          fillChar = "";
          eolChar = "";
          showCurrContext = true;
        };
        cursorWordline = {
          enable = true;
          lineTimeout = 0;
        };
      };
      vim.statusline.lualine = {
        enable = true;
        theme = "onedark";
      };
      vim.theme = {
        enable = true;
        name = "onedark";
        style = "darker";
      };
      vim.autopairs.enable = true;
      vim.autocomplete = {
        enable = true;
        type = "nvim-cmp";
      };
      vim.filetree.nvimTreeLua.enable = true;
      vim.tabline.nvimBufferline.enable = true;
      vim.treesitter.context.enable = true;
      vim.keys = {
        enable = true;
        whichKey.enable = true;
      };
      vim.telescope.enable = true;
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
