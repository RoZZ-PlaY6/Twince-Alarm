import 'package:flutter/material.dart';
import 'package:twince_alarm/services/backup_service.dart';
import 'package:twince_alarm/theme/twince_theme.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, this.onRestored});
  final Future<void> Function()? onRestored;
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _backup = BackupService();
  bool _busy = false;
  String? _currentName;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    try {
      final name = await _backup.currentName();
      if (mounted) setState(() => _currentName = name);
    } catch (_) {
      if (mounted) setState(() => _currentName = null);
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _createBackup() async {
    setState(() => _busy = true);
    try {
      final json = await _backup.create();
      final saved = await _backup.save(json);
      if (saved) await _loadCurrent();
      _message(
        saved
            ? 'New backup saved and set as current.'
            : 'Backup save cancelled.',
      );
    } catch (error) {
      _message('Could not create backup: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup() async {
    setState(() => _busy = true);
    try {
      final raw = await _backup.choose();
      if (raw == null) {
        _message('Import cancelled.');
        return;
      }
      final backup = BackupService.validate(raw);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace current data?'),
          content: const Text(
            'Restoring this backup replaces your current alarms, plans, week settings and sound preferences. Current snoozes are removed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        _message('Import cancelled.');
        return;
      }
      final result = await _backup.restore(backup);
      String? currentWarning;
      try {
        await _backup.useSelected();
        await _loadCurrent();
      } catch (error) {
        currentWarning = 'The file could not be set as current: $error';
      }
      await widget.onRestored?.call();
      final warnings = <String>[?currentWarning];
      if (result['exactAlarm'] != true) {
        warnings.add(
          'Enable exact alarms in system settings or retry scheduling.',
        );
      }
      if (result['notifications'] != true) {
        warnings.add(
          'Enable notifications for Twince Alarm in system settings.',
        );
      }
      if (result['fullScreenIntent'] != true) {
        warnings.add(
          'Enable full-screen alarm notifications in system settings.',
        );
      }
      if (result['missingSounds'] == true) {
        warnings.add(
          'Some sounds are unavailable on this device and use the default.',
        );
      }
      _message(['Backup restored.', ...warnings].join(' '));
    } catch (error) {
      _message('Could not import backup: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _offerSaveAs(String message) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Save a copy?'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save as'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _saveCurrent() async {
    setState(() => _busy = true);
    try {
      final json = await _backup.create();
      if (await _backup.saveCurrent(json)) {
        _message('Current backup updated.');
      } else if (await _offerSaveAs(
        'In-place saving is unavailable, or the current filename does not follow the backup naming rule. Save a new copy or choose a replacement in the system picker.',
      )) {
        final saved = await _backup.save(
          json,
          suggestedName:
              _currentName != null && BackupService.validFilename(_currentName!)
              ? _currentName
              : null,
        );
        if (saved) await _loadCurrent();
        _message(
          saved
              ? 'Backup saved to the selected location and set as current.'
              : 'Save cancelled; current backup unchanged.',
        );
      }
    } catch (error) {
      _message('Could not save current backup: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename() async {
    var input = _currentName ?? '';
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename backup file'),
        content: TextFormField(
          initialValue: input,
          onChanged: (value) => input = value,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Filename',
            helperText: 'Start with TWINCEALARM_ and end with .json',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, input.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (newName == null || !mounted) return;
    if (!BackupService.validFilename(newName)) {
      _message('Filename must start with TWINCEALARM_ and end with .json.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (await _backup.rename(newName)) {
        await _loadCurrent();
        _message('Backup file renamed.');
      } else if (await _offerSaveAs(
        'This provider cannot rename the file. Save a fresh backup under the new name; the original file will remain.',
      )) {
        final saved = await _backup.save(
          await _backup.create(),
          suggestedName: newName,
        );
        if (saved) await _loadCurrent();
        _message(
          saved
              ? 'A new backup was saved and set as current; the original remains.'
              : 'Save cancelled; current backup unchanged.',
        );
      }
    } catch (error) {
      _message('Could not rename backup: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TwinceColors.bg0,
      appBar: AppBar(
        title: const Text('Backup'),
        backgroundColor: TwinceColors.bg0,
        foregroundColor: TwinceColors.cyan,
      ),
      body: TwinceBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 40).clamp(
                    0,
                    double.infinity,
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Save or restore your alarms, plans and preferences.',
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _busy ? null : _importBackup,
                            icon: const Icon(Icons.download),
                            label: const Text('Import backup'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _busy || _currentName == null
                                ? null
                                : _saveCurrent,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Save to current backup'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _createBackup,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Create new backup'),
                          ),
                          const Spacer(),
                          const SizedBox(height: 32),
                          Text(
                            'Current backup: ${_currentName ?? 'None selected'}',
                            key: const Key('current-backup'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: _busy || _currentName == null
                                ? null
                                : _rename,
                            child: const Text('Rename backup file'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
