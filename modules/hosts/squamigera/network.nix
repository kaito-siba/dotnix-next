{
  flake.modules.darwin."hosts/squamigera" = {
    networking = {
      # Display name for Finder / AirDrop stays capitalized; the unix and
      # Bonjour names are lowercase so they match the flake attribute and
      # hostname-based resolution actually works.
      computerName = "Squamigera";
      hostName = "squamigera";
      localHostName = "squamigera";
    };
  };
}
