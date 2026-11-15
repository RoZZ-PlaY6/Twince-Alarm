import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:twince_alarm/services/alarm_bridge.dart';
import 'package:twince_alarm/services/plan_week.dart';

/// Version 1 uses sound titles, never Android content URIs. Titles are resolved
/// against the destination device and missing/ambiguous tones use the default.
class BackupService {
  BackupService({AlarmBridge? bridge})
    : _bridge = bridge ?? AlarmBridge.instance;
  final AlarmBridge _bridge;
  static const _channel = MethodChannel('com.twince.alarm/backup');

  Future<String> create() async {
    final sounds = await _bridge.listSounds();
    String? name(String uri) {
      if (uri.isEmpty) return null;
      final matches = sounds.where((s) => s.uri == uri).toList();
      if (matches.length != 1 ||
          sounds.where((s) => s.name == matches.first.name).length != 1) {
        throw FormatException(
          'A selected sound cannot be identified portably. Choose a listed, uniquely named alarm sound and try again.',
        );
      }
      return matches.first.name;
    }

    final alarms = await _bridge.getAlarms();
    final rawPlans = await _bridge.loadPlanLibrary();
    final plans = rawPlans.isEmpty
        ? {'weekParityMapping': 2, 'plans': []}
        : jsonDecode(rawPlans);
    final data = {
      'app': 'com.twince.alarm',
      'schemaVersion': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'alarms': [
        for (final alarm in alarms)
          {
            'id': alarm.id,
            'hour': alarm.hour,
            'minute': alarm.minute,
            'label': alarm.label,
            'subtitle': alarm.subtitle,
            'enabled': alarm.enabled,
            'vibrate': alarm.vibrate,
            'sound': name(alarm.soundUri),
            'repeatDays': alarm.repeatDays,
            'weekTags': alarm.weekTags,
          },
      ],
      'planLibrary': plans,
      'sounds': {
        'last': name(await _bridge.loadLastAlarmSound()),
        'favorites': [
          for (final uri in await _bridge.loadFavoriteAlarmSounds()) name(uri),
        ],
      },
    };
    final result = const JsonEncoder.withIndent('  ').convert(data);
    validate(result);
    return result;
  }

  Future<bool> save(String json, {String? suggestedName}) async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final filename =
        'TWINCEALARM_${now.year}-${two(now.month)}-${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}.json';
    return await _channel.invokeMethod<bool>('save', {
          'name': suggestedName ?? filename,
          'content': json,
        }) ??
        false;
  }

  Future<String?> currentName() async {
    final info = await _channel.invokeMapMethod<String, dynamic>('current');
    return info?['name'] as String?;
  }

  Future<void> useSelected() => _channel.invokeMethod<void>('useSelected');

  Future<bool> saveCurrent(String json) async =>
      await _channel.invokeMethod<bool>('saveCurrent', {'content': json}) ??
      false;

  Future<bool> rename(String name) async =>
      await _channel.invokeMethod<bool>('rename', {'name': name}) ?? false;

  static bool validFilename(String name) =>
      name.startsWith('TWINCEALARM_') &&
      name.endsWith('.json') &&
      name.length > 'TWINCEALARM_.json'.length &&
      !name.contains('/') &&
      !name.contains(r'\');

  Future<String?> choose() => _channel.invokeMethod<String>('choose');

  Future<Map<String, bool>> restore(Map<String, dynamic> data) async {
    final available = await _bridge.listSounds();
    var missing = false;
    String resolve(Object? value) {
      if (value == null) return '';
      final matches = available
          .where((s) => s.name == value && s.uri.isNotEmpty)
          .toList();
      if (matches.length != 1) {
        missing = true;
        return '';
      }
      return matches.single.uri;
    }

    final alarms = <Map<String, dynamic>>[];
    for (final raw in data['alarms'] as List) {
      final alarm = Map<String, dynamic>.from(raw as Map);
      alarm['soundUri'] = resolve(alarm.remove('sound'));
      alarms.add(alarm);
    }
    final sounds = data['sounds'] as Map;
    final last = resolve(sounds['last']);
    final favorites = <String>[];
    for (final sound in sounds['favorites'] as List) {
      final uri = resolve(sound);
      if (!favorites.contains(uri)) favorites.add(uri);
    }
    final result = await _channel.invokeMapMethod<String, bool>('restore', {
      'alarms': alarms,
      'planLibrary': jsonEncode(data['planLibrary']),
      'lastSound': last,
      'favoriteSounds': favorites,
    });
    return {...?result, 'missingSounds': missing};
  }

  static Map<String, dynamic> validate(String raw) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const FormatException('The file is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('The backup must be a JSON object.');
    }
    if (decoded['app'] != 'com.twince.alarm') {
      throw const FormatException(
        'This is not a Twince Alarm backup. Twince backups are not compatible.',
      );
    }
    if (decoded['schemaVersion'] is! int || decoded['schemaVersion'] != 1) {
      throw const FormatException('This backup version is not supported.');
    }
    if (decoded['createdAt'] is! String ||
        DateTime.tryParse(decoded['createdAt'] as String) == null) {
      throw const FormatException('Invalid backup creation timestamp.');
    }
    Never invalid(String part) =>
        throw FormatException('Invalid backup: $part.');
    bool integer(Object? value, int min, int max) =>
        value is int && value >= min && value <= max;
    bool sound(Object? value) =>
        value == null ||
        value is String && value.isNotEmpty && !value.contains('://');
    final alarms = decoded['alarms'];
    if (alarms is! List) invalid('alarms must be a list');
    final ids = <int>{};
    for (final item in alarms) {
      if (item is! Map) invalid('alarm must be an object');
      if (!integer(item['id'], 1, 2147483646) || !ids.add(item['id'] as int)) {
        invalid('alarm IDs must be unique positive integers');
      }
      if (!integer(item['hour'], 0, 23) ||
          !integer(item['minute'], 0, 59) ||
          item['label'] is! String ||
          item['subtitle'] is! String ||
          item['enabled'] is! bool ||
          item['vibrate'] is! bool ||
          !sound(item['sound'])) {
        invalid('alarm fields');
      }
      final days = item['repeatDays'];
      if (days is! List ||
          days.any((d) => !integer(d, 1, 7)) ||
          days.toSet().length != days.length) {
        invalid('repeat days');
      }
      final tags = item['weekTags'];
      if (tags is! List ||
          tags.any((t) => t != 'Z' && t != 'F' && t != 'both') ||
          tags.toSet().length != tags.length ||
          tags.contains('both') && tags.length != 1) {
        invalid('week tags');
      }
    }
    final sounds = decoded['sounds'];
    if (sounds is! Map ||
        !sound(sounds['last']) ||
        sounds['favorites'] is! List ||
        (sounds['favorites'] as List).any((v) => !sound(v))) {
      invalid('sound preferences');
    }
    final library = decoded['planLibrary'];
    if (library is! Map ||
        library['weekParityMapping'] != 2 ||
        library['plans'] is! List) {
      invalid('plan library');
    }
    if (library.containsKey('weekCycle') &&
        WeekCycle.fromJson(library['weekCycle']) == null) {
      invalid('week cycle');
    }
    final planIds = <String>{};
    final referenced = <int>{};
    for (final plan in library['plans'] as List) {
      if (plan is! Map ||
          plan['sourcePlanId'] is! String ||
          (plan['sourcePlanId'] as String).isEmpty ||
          !planIds.add(plan['sourcePlanId'] as String) ||
          plan['title'] is! String ||
          !['every', 'evenOdd'].contains(plan['weekMode']) ||
          plan['sourceFormat'] is! String ||
          plan['sourceVersion'] is! int ||
          plan['exportedAt'] is! String ||
          plan['timezone'] is! String ||
          plan['tasks'] is! List) {
        invalid('plan fields');
      }
      final taskIds = <String>{};
      for (final task in plan['tasks'] as List) {
        if (task is! Map ||
            task['sourceTaskId'] is! String ||
            (task['sourceTaskId'] as String).isEmpty ||
            !taskIds.add(task['sourceTaskId'] as String) ||
            task['title'] is! String ||
            task['description'] is! String ||
            !integer(task['hour'], 0, 23) ||
            !integer(task['minute'], 0, 59) ||
            task['enabled'] is! bool ||
            task['repeatDays'] is! List ||
            (task['repeatDays'] as List).any((d) => !integer(d, 1, 7)) ||
            task['weekAssignments'] is! List ||
            (task['weekAssignments'] as List).any(
              (w) => w != 'z' && w != 'f',
            ) ||
            task['alarmId'] is! int ||
            !ids.contains(task['alarmId']) ||
            !referenced.add(task['alarmId'] as int)) {
          invalid('plan task or alarm reference');
        }
      }
    }
    return decoded;
  }
}
