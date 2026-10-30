{
  flake.modules.darwin.desktop =
    { config, ... }:
    {
      homebrew.casks = [ "google-japanese-ime" ];

      # The cask's pkg unloads the Converter and Renderer launch agents when it
      # (re)installs, but never loads them back into the logged-in session. The
      # input method itself keeps running, so typing switches to Japanese yet
      # nothing converts until the next login. postActivation runs after the
      # homebrew step, so load whichever agent is missing and restart the input
      # method so it reconnects to them. Nothing to do without a GUI session.
      system.activationScripts.postActivation.text = ''
        uid=$(id -u ${config.system.primaryUser})
        if launchctl print "gui/$uid" >/dev/null 2>&1; then
          reloaded=
          for agent in Converter Renderer; do
            label=com.google.inputmethod.Japanese.$agent
            plist=/Library/LaunchAgents/$label.plist
            if [ -f "$plist" ] && ! launchctl print "gui/$uid/$label" >/dev/null 2>&1; then
              echo "reloading Google Japanese Input $agent..." >&2
              launchctl bootstrap "gui/$uid" "$plist" && reloaded=1
            fi
          done
          if [ -n "$reloaded" ]; then
            pkill -U "$uid" -x GoogleJapaneseInput || true
          fi
        fi
      '';
    };
}
