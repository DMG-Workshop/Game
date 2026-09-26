# Marching Order — the app

The game on a screen, for Android, iOS and the web. It is the same
`GameConsole` the terminal client drives, from `packages/game_core`, with a
row of chips for what can be done here and a line to type anything else.

```
dart run tool/sync_assets.dart   # copy the campaign in from the repository
flutter run
```

The campaign and rules content are copied into `assets/`, not committed:
the repository keeps one copy of each file. Build for the web with
`--no-web-resources-cdn` so the page carries its own renderer.
