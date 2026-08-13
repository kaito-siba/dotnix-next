{
  # Authorized key for the work mac, carried over from the agenix setup in the
  # old repo (the pubkey used to come from the private nix-secrets flake).
  #
  # sshd picks the file up through the default AuthorizedKeysFile entry
  # /etc/ssh/authorized_keys.d/%u. It deliberately does not go through
  # users.users.<name>.openssh.authorizedKeys.keyFiles: those are read at build
  # time and would end up world-readable in the store, whereas sops only
  # decrypts during activation.
  flake.modules.nixos."hosts/albiflora" = {
    sops.secrets."w963n-authorized-keys" = {
      sopsFile = ./secrets/authorized-keys.yaml;
      path = "/etc/ssh/authorized_keys.d/w963n";
      owner = "w963n";
      mode = "0400";
    };
  };
}
