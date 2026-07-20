{
  flake.modules.darwin.desktop = {
    homebrew = {
      taps = [
        {
          name = "nikitabobko/tap";
          trusted = true;
        }
      ];

      casks = [ "aerospace" ];
    };
  };
}
