{
  flake.modules.homeManager.dev =
    { inputs, pkgs, ... }:
    let
      # `default` bundles all driver extras, including snowflake, whose
      # snowflake-connector-python fails its test suite on Python 3.14.
      # Build via makeSqlit with every extra except snowflake to avoid it.
      sqlitPkg = inputs.sqlit.lib.${pkgs.stdenv.hostPlatform.system}.makeSqlit {
        extras = [
          "ssh"
          "postgres"
          "cockroachdb"
          "mysql"
          "duckdb"
          "bigquery"
          "d1"
        ];
      };

      sqlitPython =
        if sqlitPkg ? python then
          sqlitPkg.python
        else if sqlitPkg ? passthru && sqlitPkg.passthru ? python then
          sqlitPkg.passthru.python
        else
          pkgs.python3;

      pyPkgs = sqlitPython.pkgs;
      driverPath = pyPkgs.makePythonPath [
        pyPkgs.pymysql
        pyPkgs.psycopg2-binary
        pyPkgs.sshtunnel
        pyPkgs.pyathena
      ];

      sqlitWithDrivers = pkgs.symlinkJoin {
        name = "sqlit-with-drivers";
        paths = [ sqlitPkg ];
        buildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/sqlit \
            --prefix PYTHONPATH : ${driverPath}
        '';
      };

      # ~/.config/sqlit/keymap.json: 既定キーマップへの差分のみを書く。
      keymap = {
        keymap.action_keys = {
          query_normal.edit_query_in_editor = "ctrl+g";
        };
      };
    in
    {
      home.packages = [ sqlitWithDrivers ];

      xdg.configFile."sqlit/keymap.json".text = builtins.toJSON keymap;
    };
}
