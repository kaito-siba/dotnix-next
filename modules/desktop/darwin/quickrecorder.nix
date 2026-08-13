{
  flake.modules.darwin.desktop = {
    homebrew = {
      taps = [
        {
          name = "lihaoyun6/tap";
          trusted = true;
        }
      ];

      casks = [ "quickrecorder" ];
    };
  };
}
