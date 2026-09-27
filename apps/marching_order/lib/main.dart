import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart';
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
    if (line == GameController.tradeCommand) {
      _openTrade();
      return;
    }
    widget.game.send(line);
    _input.clear();
  }

  /// The shop, as a sheet: what is for sale with a Buy button each, and
  /// what the party carries with a Sell button each. Every button is an
  /// ordinary "buy" or "sell" command, so the log records it as typed.
  void _openTrade() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListenableBuilder(
          listenable: widget.game,
          builder: (context, _) =>
              _TradeSheet(game: widget.game, scroll: scroll),
        ),
      ),
    );
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

class _TradeSheet extends StatelessWidget {
  const _TradeSheet({required this.game, required this.scroll});

  final GameController game;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coin = game.session.inventory.coin;
    final ready = game.isIdle && game.canTrade;
    final wares = game.wares;
    final pack = game.sellable;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(game.shopName, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('The party has ${formatCoin(coin)}.'),
        if (game.priceChange != 0) ...[
          const SizedBox(height: 12),
          _PriceBanner(percent: game.priceChange),
        ],
        const SizedBox(height: 16),
        Text('For sale', style: theme.textTheme.titleMedium),
        if (wares.isEmpty) const Text('Nothing on the shelf.'),
        for (final row in wares)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(row.item.name),
            subtitle: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'level ${row.item.level} ${row.item.type} · '),
                  // A haggled price shows what it was, struck through.
                  if (row.price != row.item.price) ...[
                    TextSpan(
                      text: formatCoin(row.item.price),
                      style: const TextStyle(
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const TextSpan(text: ' '),
                  ],
                  TextSpan(
                    text: formatCoin(row.price),
                    style: row.price < row.item.price
                        ? TextStyle(
                            color: theme.colorScheme.tertiary,
                            fontWeight: FontWeight.w600,
                          )
                        : null,
                  ),
                ],
              ),
            ),
            trailing: FilledButton.tonal(
              onPressed: ready && row.price <= coin
                  ? () => game.send('buy ${row.item.name}')
                  : null,
              child: const Text('Buy'),
            ),
          ),
        const SizedBox(height: 16),
        Text('Your pack', style: theme.textTheme.titleMedium),
        if (pack.isEmpty) const Text('Nothing to sell.'),
        for (final row in pack)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              row.copies > 1
                  ? '${row.item.name} ×${row.copies}'
                  : row.item.name,
            ),
            subtitle: Text(
              row.inUse
                  ? 'In use: take it off to sell it'
                  : 'Sells for ${formatCoin(row.price)}',
            ),
            trailing: OutlinedButton(
              onPressed: ready && !row.inUse
                  ? () => game.send('sell ${row.item.name}')
                  : null,
              child: const Text('Sell'),
            ),
          ),
      ],
    );
  }
}

/// What the keeper has agreed to, said where the prices are.
class _PriceBanner extends StatelessWidget {
  const _PriceBanner({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final discount = percent < 0;
    final ink = discount ? scheme.onTertiaryContainer : scheme.onErrorContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: discount ? scheme.tertiaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(discount ? Icons.sell_outlined : Icons.trending_up, color: ink),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              discount
                  ? '${-percent}% off everything, for you.'
                  : 'Prices are $percent% up, for you.',
              style: TextStyle(color: ink, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
