{
  flake.modules.homeManager.sqlit =
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
    in
    {
      home.packages = [ sqlitWithDrivers ];
    };
}
