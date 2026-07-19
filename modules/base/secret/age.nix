{
  flake.modules.homeManager.base =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      ageKeyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    in
    {
      home.packages = with pkgs; [
        sops
        age
        ssh-to-age
      ];

      home.sessionVariables = {
        SOPS_AGE_KEY_FILE = ageKeyFile;
      };

      home.activation.ensureSopsAgeKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        key_file="${ageKeyFile}"
        key_dir="$(dirname "$key_file")"

        if [ ! -e "$key_file" ]; then
          mkdir -p "$key_dir"
          chmod 700 "$key_dir"
          ${pkgs.age}/bin/age-keygen -o "$key_file"
          chmod 600 "$key_file"
          echo "Generated age key at $key_file"
        fi
      '';
    };
}
