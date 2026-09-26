// Copies the campaign and rules content into assets/, where Flutter can
// bundle it. Run before building or testing:
//
//   dart run tool/sync_assets.dart
//
// The copies are not committed: the repository keeps one of each file, and
// the app and the terminal read the same data.
import 'dart:io';

const _sources = {
  '../../campaigns/shattered_seals': 'assets/campaign',
  '../../content/pf2e_remaster': 'assets/content',
};
const _sample = '../../packages/pf2e_core/test/fixtures/korash.json';

void main() {
  for (final MapEntry(key: from, value: to) in _sources.entries) {
    final target = Directory(to);
    if (target.existsSync()) target.deleteSync(recursive: true);
    target.createSync(recursive: true);
    for (final file in Directory(from).listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      file.copySync('$to/${file.uri.pathSegments.last}');
    }
  }
  Directory('assets/characters').createSync(recursive: true);
  File(_sample).copySync('assets/characters/korash.json');
  stdout.writeln('assets/ synced from the repository.');
}
