import 'dart:convert';

import 'package:pf2e_core/pf2e_core.dart';

import 'scene.dart';

/// Thrown when adventure data cannot be read.
class AdventureFormatException implements Exception {
  AdventureFormatException(this.message);

  final String message;

  @override
  String toString() => 'AdventureFormatException: $message';
}

/// Reads adventures from JSON and checks them for authoring mistakes.
///
/// Content is data rather than code so scenes can be written, reviewed, and
/// shipped without a rebuild.
class AdventureLoader {
  const AdventureLoader();

  Adventure fromJson(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw AdventureFormatException('Not valid JSON: ${e.message}');
    }
    if (decoded is! Map) {
      throw AdventureFormatException(
          'Expected a JSON object at the top level.');
    }
    return fromMap(decoded.cast<String, Object?>());
  }

  Adventure fromMap(Map<String, Object?> root) {
    final id = _requireString(root, 'id');
    final title = _requireString(root, 'title');
    final startSceneId = _requireString(root, 'startScene');

    final rawScenes = root['scenes'];
    if (rawScenes is! List || rawScenes.isEmpty) {
      throw AdventureFormatException('Adventure "$id" has no scenes.');
    }

    final scenes = <String, Scene>{};
    for (final entry in rawScenes) {
      if (entry is! Map) {
        throw AdventureFormatException(
            'Adventure "$id" has a malformed scene.');
      }
      final scene = _readScene(entry.cast<String, Object?>());
      if (scenes.containsKey(scene.id)) {
        throw AdventureFormatException('Duplicate scene id "${scene.id}".');
      }
      scenes[scene.id] = scene;
    }

    final adventure = Adventure(
      id: id,
      title: title,
      startSceneId: startSceneId,
      scenes: scenes,
    );

    final problems = validate(adventure);
    if (problems.isNotEmpty) {
      throw AdventureFormatException(
          'Adventure "$id" is inconsistent:\n  ${problems.join('\n  ')}');
    }
    return adventure;
  }

  /// Structural problems that would strand a player: a missing start scene, a
  /// transition to a scene that does not exist, or an option that can never
  /// produce an outcome.
  List<String> validate(Adventure adventure) {
    final problems = <String>[];
    if (!adventure.scenes.containsKey(adventure.startSceneId)) {
      problems.add('start scene "${adventure.startSceneId}" does not exist');
    }

    for (final scene in adventure.scenes.values) {
      final optionIds = <String>{};
      for (final option in scene.options) {
        if (!optionIds.add(option.id)) {
          problems.add('scene "${scene.id}" repeats option id "${option.id}"');
        }

        final targets = <Outcome?>[
          option.automatic,
          ...option.outcomes.values,
        ];
        for (final outcome in targets) {
          final goTo = outcome?.goTo;
          if (goTo != null && !adventure.scenes.containsKey(goTo)) {
            problems.add(
                'scene "${scene.id}" option "${option.id}" leads to missing '
                'scene "$goTo"');
          }
        }

        if (option.check == null && option.automatic == null) {
          problems.add(
              'scene "${scene.id}" option "${option.id}" has neither a check '
              'nor an outcome');
        }
        if (option.check != null && option.outcomes.isEmpty) {
          problems.add(
              'scene "${scene.id}" option "${option.id}" rolls a check but '
              'defines no outcomes');
        }
      }

      if (scene.options.isEmpty && !scene.isEnding) {
        problems.add('scene "${scene.id}" is a dead end but is not an ending');
      }
    }
    return problems;
  }

  /// Stat keys in the adventure that [stats] cannot resolve.
  ///
  /// Separate from [validate] because it needs a character: a typo such as
  /// `lore:undad` is only detectable against a real sheet.
  List<String> unresolvableStats(Adventure adventure, DerivedStats stats) {
    final bad = <String>{};
    for (final scene in adventure.scenes.values) {
      for (final option in scene.options) {
        final key = option.check?.statKey;
        if (key != null && stats.statByKey(key) == null) bad.add(key);
        final gateKey = option.gate.minProficiencyStat;
        if (gateKey != null && stats.statByKey(gateKey) == null) {
          bad.add(gateKey);
        }
      }
    }
    return bad.toList()..sort();
  }

  Scene _readScene(Map<String, Object?> raw) {
    final id = _requireString(raw, 'id');
    return Scene(
      id: id,
      title: _requireString(raw, 'title'),
      body: _requireString(raw, 'body'),
      isEnding: raw['isEnding'] == true,
      options: [
        for (final entry in _list(raw['options']))
          if (entry is Map) _readOption(entry.cast<String, Object?>(), id),
      ],
    );
  }

  SceneOption _readOption(Map<String, Object?> raw, String sceneId) {
    final id = _requireString(raw, 'id');

    StatCheck? check;
    if (raw['check'] case final Map<Object?, Object?> rawCheck) {
      final c = rawCheck.cast<String, Object?>();
      check = StatCheck(
        statKey: _requireString(c, 'stat'),
        dc: _requireInt(c, 'dc'),
      );
    }

    final outcomes = <DegreeOfSuccess, Outcome>{};
    if (raw['outcomes'] case final Map<Object?, Object?> rawOutcomes) {
      for (final entry in rawOutcomes.cast<String, Object?>().entries) {
        final degree = _degreeFromKey(entry.key);
        if (degree == null) {
          throw AdventureFormatException(
              'Scene "$sceneId" option "$id" has unknown degree '
              '"${entry.key}".');
        }
        if (entry.value is! Map) {
          throw AdventureFormatException(
              'Scene "$sceneId" option "$id" has a malformed '
              '"${entry.key}" outcome.');
        }
        outcomes[degree] =
            _readOutcome((entry.value! as Map).cast<String, Object?>());
      }
    }

    Outcome? automatic;
    if (raw['outcome'] case final Map<Object?, Object?> rawAuto) {
      automatic = _readOutcome(rawAuto.cast<String, Object?>());
    }

    return SceneOption(
      id: id,
      label: _requireString(raw, 'label'),
      check: check,
      outcomes: outcomes,
      automatic: automatic,
      gate: _readGate(raw['requires']),
    );
  }

  Outcome _readOutcome(Map<String, Object?> raw) => Outcome(
        text: _requireString(raw, 'text'),
        goTo: raw['goTo']?.toString(),
        setFlags: _stringList(raw['setFlags']),
        clearFlags: _stringList(raw['clearFlags']),
      );

  OptionGate _readGate(Object? raw) {
    if (raw is! Map) return const OptionGate();
    final gate = raw.cast<String, Object?>();

    String? statKey;
    Proficiency? minimum;
    if (gate['minProficiency'] case final Map<Object?, Object?> rawMin) {
      final m = rawMin.cast<String, Object?>();
      statKey = _requireString(m, 'stat');
      minimum = _proficiencyFromKey(_requireString(m, 'rank'));
      if (minimum == null) {
        throw AdventureFormatException(
            'Unknown proficiency rank "${m['rank']}".');
      }
    }

    return OptionGate(
      requiredFlags: _stringList(gate['flags']),
      forbiddenFlags: _stringList(gate['notFlags']),
      minProficiencyStat: statKey,
      minProficiency: minimum,
    );
  }

  static DegreeOfSuccess? _degreeFromKey(String key) {
    final needle = key.trim().toLowerCase().replaceAll(RegExp(r'[_\- ]'), '');
    return switch (needle) {
      'criticalsuccess' || 'critsuccess' => DegreeOfSuccess.criticalSuccess,
      'success' => DegreeOfSuccess.success,
      'failure' || 'fail' => DegreeOfSuccess.failure,
      'criticalfailure' || 'critfailure' => DegreeOfSuccess.criticalFailure,
      _ => null,
    };
  }

  static Proficiency? _proficiencyFromKey(String key) {
    final needle = key.trim().toLowerCase();
    for (final p in Proficiency.values) {
      if (p.name == needle) return p;
    }
    return null;
  }

  static List<Object?> _list(Object? raw) => raw is List ? raw : const [];

  static List<String> _stringList(Object? raw) => [
        for (final item in _list(raw))
          if (item != null) item.toString(),
      ];

  static String _requireString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null || value.toString().trim().isEmpty) {
      throw AdventureFormatException('Missing required field "$key".');
    }
    return value.toString();
  }

  static int _requireInt(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is int) return value;
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
    throw AdventureFormatException('Field "$key" must be an integer.');
  }
}
