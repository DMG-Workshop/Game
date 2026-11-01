{{flutter_js}}
{{flutter_build_config}}

// Flutter's default passes service worker settings here, which would swap
// revalidate_worker.js for Flutter's own worker, one that only unregisters
// itself and reloads the page. Without them, the loader leaves workers alone.
_flutter.loader.load();
