import 'package:flutter/material.dart';
import 'package:pf2e_core/pf2e_core.dart';

import 'game_controller.dart';

void main() => runApp(const MarchingOrderApp());

class MarchingOrderApp extends StatelessWidget {
  const MarchingOrderApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Marching Order',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF8B1E1E),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: const TitleScreen(),
  );
}

/// Continue, or start a new game with a character from Pathbuilder.
class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key});

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  final _pasted = TextEditingController();
  bool? _hasSave;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    GameController.hasSave().then((v) => setState(() => _hasSave = v));
  }

  Future<void> _open(Future<GameController> Function() make) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final game = await make();
      if (!mounted) return;
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => GameScreen(game: game)));
      final has = await GameController.hasSave();
      setState(() => _hasSave = has);
    } on PathbuilderImportException catch (e) {
      setState(() => _error = 'That is not a Pathbuilder export: ${e.message}');
    } on FormatException catch (e) {
      setState(() => _error = 'That is not a Pathbuilder export: ${e.message}');
    } on StateError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Marching Order', style: theme.textTheme.displaySmall),
                const SizedBox(height: 4),
                Text(
                  'Campaign I: Shattered Seals',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 32),
                if (_hasSave ?? false)
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _open(GameController.resume),
                    child: const Text('Continue'),
                  ),
                const SizedBox(height: 24),
                Text('New game', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  'Paste the JSON Pathbuilder 2e exports for your '
                  'character (Menu, then Export, then Export JSON), or play the '
                  'sample character.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pasted,
                  onChanged: (_) => setState(() {}),
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '{"success": true, "build": {...}}',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: _busy || _pasted.text.trim().isEmpty
                          ? null
                          : () => _open(
                              () => GameController.start([_pasted.text.trim()]),
                            ),
                      child: const Text('Play my character'),
                    ),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _open(
                              () async => GameController.start([
                                await GameController.demoCharacter(),
                              ]),
                            ),
                      child: const Text('Play the sample (Korash, level 6)'),
                    ),
                  ],
                ),
                if (_hasSave ?? false) ...[
                  const SizedBox(height: 8),
                  const Text('Starting a new game replaces the saved one.'),
                ],
                if (_error case final error?) ...[
                  const SizedBox(height: 16),
                  Text(error, style: TextStyle(color: theme.colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The game: the log, the chips, and a line to type in.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.game});

  final GameController game;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.game.addListener(_changed);
  }

  @override
  void dispose() {
    widget.game.removeListener(_changed);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _send(String line) {
    widget.game.send(line);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(game.session.currentRoom.title),
        actions: [
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.save_outlined),
            onPressed: () async {
              await game.save();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Saved on this device.')),
                );
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  game.log,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            ),
            if (!game.isOver) ...[
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (final chip in game.chips)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ActionChip(
                          label: Text(chip.label),
                          onPressed: () => _send(chip.command),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: TextField(
                  controller: _input,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  autocorrect: false,
                  decoration: InputDecoration(
                    prefixText: game.prompt,
                    border: const OutlineInputBorder(),
                    hintText: 'or type a command',
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: () => _send(_input.text),
                    ),
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
