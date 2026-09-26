import 'dart:io';

import 'package:game_core/game_core.dart';

const _defaultDir = '../../campaigns/shattered_seals';

/// Reports what a campaign's data still owes.
///
///   dart run game_core:survey
///   dart run game_core:survey path/to/campaign
///
/// Exits non-zero only for problems that would strand a player right now —
/// an exit to nowhere, an NPC in a room that does not exist. Content that is
/// merely unwritten is reported and forgiven, because a campaign is
/// incomplete for most of the time it is being written.
void main(List<String> args) {
  final dir = args.where((a) => !a.startsWith('--')).firstOrNull ?? _defaultDir;

  String? read(String name) {
    final file = File('$dir/$name');
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  final world = read('world_config.json');
  final locations = read('locations.json');
  final npcs = read('npcs_and_dialogue.json');
  if (world == null || locations == null || npcs == null) {
    stderr.writeln('Not a campaign directory: $dir');
    stderr.writeln('Expected world_config.json, locations.json and '
        'npcs_and_dialogue.json.');
    exitCode = 66;
    return;
  }

  final Campaign campaign;
  try {
    campaign = const CampaignLoader().load(
      id: dir.split('/').where((s) => s.isNotEmpty).last,
      title: dir.split('/').where((s) => s.isNotEmpty).last,
      worldConfigJson: world,
      locationsJson: locations,
      npcsJson: npcs,
      gearJson: read('gear.json'),
      arcsJson: read('campaign_arcs.json'),
      bestiaryJson: read('bestiary.json'),
      itemsJson: read('world_items.json'),
      conversationsJson: read('conversations.json'),
      economyJson: read('economy.json'),
    );
  } on CampaignFormatException catch (e) {
    stderr.writeln('Could not read the campaign: ${e.message}');
    exitCode = 65;
    return;
  }

  final report = campaign.survey();

  stdout
    ..writeln('=' * 68)
    ..writeln(campaign.world.metadata.name)
    ..writeln('${campaign.locations.towns.length} towns, '
        '${campaign.locations.rooms.length} rooms written, '
        '${campaign.npcs.length} NPCs, '
        '${campaign.conversations.length} conversations, '
        '${campaign.gear.length} items, '
        '${campaign.arcs.length} arcs, '
        '${campaign.bestiary.creatures.length} creatures, '
        '${campaign.bestiary.encounters.length} fights, '
        '${campaign.items.length} objects')
    ..writeln('=' * 68)
    ..writeln()
    ..writeln(report.render());

  if (!report.isPlayable) {
    stdout.writeln('\nNot yet walkable: an exit or an NPC points at a room '
        'that does not exist.');
    exitCode = 1;
    return;
  }
  if (!report.isClean) {
    stdout.writeln('\nWalkable, with content still to write.');
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => iterator.moveNext() ? first : null;
}
