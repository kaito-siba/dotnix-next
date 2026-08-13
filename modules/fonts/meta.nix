{
  # フォントファミリー名の一括設定。flake.meta.users と同じ要領で、
  # ghostty / noctalia / gtk などの消費側モジュールはここを参照する。
  # フォントを変えるときはこのファイルと fonts.nix / guguru.nix の
  # パッケージだけ触れば全アプリに波及する。
  flake.meta.fonts = {
    # ターミナル・エディタ向け等幅 (Nerd グリフ入り)
    coding = "Guguru Sans Code Console NF";
    # シェル UI・GTK アプリ向けサンセリフ
    ui = "IBM Plex Sans JP";
  };
}
