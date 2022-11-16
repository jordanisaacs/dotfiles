{
  pkgs,
  nur,
  dwm-flake,
  deploy-rs,
  neovim-flake,
  st-flake,
  dwl-flake,
  scripts,
  homeage,
  system,
  lib,
  jdpkgs,
  impermanence,
  nixpkgs-wayland,
  agenix,
}: let
  dwl-config = builtins.readFile ./dwl-config.c;
in {
  overlays = [
    nur.overlay
    neovim-flake.overlays.default
    nixpkgs-wayland.overlays.default
    dwl-flake.overlay."${system}"
    scripts.overlay

    (final: prev: {
      neovimWork = prev.neovimBuilder {
        config = {
          vim.lsp = {
            enable = true;
            lightbulb.enable = true;
            lspSignature.enable = true;
            nvimCodeActionMenu.enable = true;
            nix = true;
            ts = true;
            sql = true;
            go = true;
          };
          vim.statusline.lualine = {
            enable = true;
            theme = "onedark";
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
          vim.telescope = {
            enable = true;
          };
          vim.markdown = {
            enable = true;
            glow.enable = true;
          };
          vim.treesitter = {
            enable = true;
            autotagHtml = true;
            context.enable = true;
          };
          vim.keys = {
            enable = true;
            whichKey.enable = true;
          };
          vim.git = {
            enable = true;
            gitsigns.enable = true;
          };
        };
      };
      # Version of xss-lock that supports logind SetLockedHint
      xss-lock = prev.xss-lock.overrideAttrs (old: {
        src = prev.fetchFromGitHub {
          owner = "xdbob";
          repo = "xss-lock";
          rev = "7b0b4dc83ff3716fd3051e6abf9709ddc434e985";
          sha256 = "TG/H2dGncXfdTDZkAY0XAbZ80R1wOgufeOmVL9yJpSk=";
        };
      });
      # Commented out because need to update the patch
      # xorg = prev.xorg // {
      #   # Override xorgserver with patch to set x11 type
      #   xorgserver = lib.overrideDerivation prev.xorg.xorgserver (drv: {
      #     patches = drv.patches ++ [ ./x11-session-type.patch ];
      #   });
      # };
      dwmJD = dwm-flake.packages.${system}.dwmJD;
      stJD = st-flake.packages.${system}.stJD;
      weechatJD = prev.weechat.override {
        configure = {availablePlugins, ...}: {
          scripts = with prev.weechatScripts; [
            weechat-matrix
          ];
        };
      };
      agenix-cli = agenix.defaultPackage."${system}";
      deploy-rs = deploy-rs.packages."${system}".deploy-rs;
      jdpkgs = jdpkgs.packages."${system}";
      inherit homeage impermanence;
    })
  ];
}
