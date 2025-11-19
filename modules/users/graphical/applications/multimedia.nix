{ pkgs, config, lib, ... }:
with lib;
let
  cfg = config.jd.graphical.applications;
  isGraphical = let cfg = config.jd.graphical;
  in cfg.xorg.enable || cfg.wayland.enable;
in {
  options.jd.graphical.applications.multimedia = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable multimedia packages";
    };
  };

  config = mkIf (isGraphical && cfg.enable && cfg.multimedia.enable) {
    home.packages = with pkgs; [
      # paint.net replacement
      pinta

      # vector art
      inkscape

      # painting/drawing
      krita

      # photo editing
      gimp

      # pdf viewer
      kdePackages.okular

      # image viewer
      vimiv-qt

      # recording/streaming
      obs-studio

      # video editing
      kdePackages.kdenlive

      # audio
      ardour
    ];

    programs.mpv = {
      enable = true;
      config = {
        profile = "gpu-hq";
        vo = "gpu";
        hwdec = "auto-safe";
        ytdl-format =
          "ytdl-format=bestvideo[height<=?1920][fps<=?30][vcodec!=?vp9]+bestaudio/best";
      };
    };

    xdg = {
      mimeApps.defaultApplications = {
        "image/bmp" = "vimiv.desktop";
        "image/gif" = "vimiv.desktop";
        "image/jpeg" = "vimiv.desktop";
        "image/jp2" = "vimiv.desktop";
        "image/jpeg2000" = "vimiv.desktop";
        "image/jpx" = "vimiv.desktop";
        "image/png" = "vimiv.desktop";
        "image/svg" = "vimiv.desktop";
        "image/tiff" = "vimiv.desktop";

        "application/pdf" = "okularApplication_pdf.desktop";
      };

      configFile = {
        "vimiv/vimiv.conf" = {
          text = ''
            [GENERAL]
            monitor_filesystem = True
            shuffle = False
            startup_library = True
            style = default-dark

            [COMMAND]
            history_limit = 100

            [COMPLETION]
            fuzzy = False

            [SEARCH]
            ignore_case = True
            incremental = True

            [IMAGE]
            autoplay = True
            autowrite = ask
            overzoom = 1.0

            [LIBRARY]
            width = 0.3
            show_hidden = False

            [THUMBNAIL]
            size = 128

            [SLIDESHOW]
            delay = 2.0
            indicator = slideshow:

            [STATUSBAR]
            collapse_home = True
            show = True
            message_timeout = 60000
            mark_indicator = <b>*</b>
            left = {pwd}
            left_image = {index}/{total} {basename} [{zoomlevel}]
            left_thumbnail = {thumbnail-index}/{thumbnail-total} {thumbnail-name}
            left_manipulate = {basename}   {image-size}   Modified: {modified}   {processing}
            center_thumbnail = {thumbnail-size}
            center = {slideshow-indicator} {slideshow-delay} {transformation-info}
            right = {keys}  {mark-count}  {mode}
            right_image = {keys}  {mark-indicator} {mark-count}  {mode}

            [KEYHINT]
            delay = 500
            timeout = 5000

            [TITLE]
            fallback = vimiv
            image = vimiv - {basename}

            [METADATA]
            keys1 = Exif.Image.Make, Exif.Image.Model, Exif.Image.DateTime, Exif.Photo.ExposureTime, Exif.Photo.FNumber, Exif.Photo.IsoSpeedRatings, Exif.Photo.FocalLength, Exif.Photo.LensMake, Exif.Photo.LensModel, Exif.Photo.ExposureBiasValue
            keys2 = Exif.Photo.ExposureTime, Exif.Photo.FNumber, Exif.Photo.IsoSpeedRatings, Exif.Photo.FocalLength
            keys3 = Exif.Image.Artist, Exif.Image.Copyright

            [PLUGINS]
            print = default

            [ALIASES]
          '';
        };
      };
    };
  };
}
