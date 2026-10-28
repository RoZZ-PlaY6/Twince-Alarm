import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twince_alarm/models/alarm_item.dart';
import 'package:twince_alarm/models/imported_plan.dart';
import 'package:twince_alarm/services/plan_repository.dart';
import 'package:twince_alarm/services/plan_week.dart';
import 'package:twince_alarm/theme/twince_theme.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key, this.repository, this.active = true});

  final PlanRepository? repository;
  final bool active;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> with WidgetsBindingObserver {
  late final PlanRepository _repository = widget.repository ?? PlanRepository();
  bool _loading = true;
  bool _asking = false;
  Timer? _weekWatch;
  DateTime? _visibleSaturday;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _weekWatch = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _onWeekTick(),
    );
    _reload();
  }

  @override
  void dispose() {
    _weekWatch?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(PlanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _promptIfNeeded();
    }
  }

  void _promptIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.active ||
          _loading ||
          _repository.weekConfigured) {
        return;
      }
      _chooseWeek(requiredChoice: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reload(reconcile: true);
    }
  }

  Future<void> _reload({bool reconcile = false}) async {
    await _repository.load();
    if (!mounted) return;
    setState(() => _loading = false);
    _visibleSaturday = saturdayOnOrBefore(DateTime.now());
    if (!_repository.weekConfigured) {
      if (widget.active) _promptIfNeeded();
      return;
    }
    if (reconcile) await _repository.reconcile(DateTime.now());
  }

  Future<void> _onWeekTick() async {
    final saturday = saturdayOnOrBefore(DateTime.now());
    if (_visibleSaturday == saturday) return;
    _visibleSaturday = saturday;
    if (!_repository.weekConfigured) return;
    await _repository.reconcile(DateTime.now());
    if (mounted) setState(() {});
  }

  Future<void> _chooseWeek({required bool requiredChoice}) async {
    if (_asking || !mounted) return;
    _asking = true;
    bool? even;
    try {
      even = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: !requiredChoice,
        builder: (dialogContext) {
          return PopScope(
            canPop: !requiredChoice,
            child: AlertDialog(
              title: const Text('Current week'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Choose the parity of this Saturday–Friday week. It flips automatically next Saturday.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text(
                      '\u0647\u0641\u062a\u0647 \u0632\u0648\u062c (Z)\nEven week (Z)',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text(
                      '\u0647\u0641\u062a\u0647 \u0641\u0631\u062f (F)\nOdd week (F)',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      _asking = false;
    }
    if (!mounted) return;
    if (even == null) {
      if (requiredChoice && !_repository.weekConfigured) {
        _promptIfNeeded();
      }
      return;
    }
    try {
      await _repository.setCurrentWeek(even: even, now: DateTime.now());
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _import() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _PlanImportPage(repository: _repository),
      ),
    );
    if (changed == true) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TwinceBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Plans',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Import Plan',
                      onPressed: _repository.weekConfigured ? _import : null,
                      icon: const Icon(Icons.add, color: TwinceColors.cyan),
                    ),
                  ],
                ),
              ),
              if (_repository.weekConfigured)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          currentWeekCaption(
                            _repository.weekCycle!,
                            DateTime.now(),
                          ),
                          style: const TextStyle(
                            color: TwinceColors.cyan,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit current week',
                        onPressed: () => _chooseWeek(requiredChoice: false),
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: TwinceColors.cyan,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: TwinceColors.cyan,
                        ),
                      )
                    : !_repository.weekConfigured
                    ? const Center(
                        child: Text(
                          'Choose the current week to continue.',
                          style: TextStyle(color: TwinceColors.muted),
                        ),
                      )
                    : _repository.plans.isEmpty
                    ? const _EmptyPlans()
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: [
                          for (final plan in _repository.plans)
                            _PlanCard(
                              plan: plan,
                              onOpen: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => _PlanDetailPage(
                                      plan: plan,
                                      repository: _repository,
                                      evenWeek: _repository.isEvenWeekOn(
                                        DateTime.now(),
                                      ),
                                    ),
                                  ),
                                );
                                await _reload();
                              },
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPlans extends StatelessWidget {
  const _EmptyPlans();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Import a Plan exported from Twince.',
          textAlign: TextAlign.center,
          style: TextStyle(color: TwinceColors.muted),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onOpen});

  final ImportedPlan plan;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: TwinceColors.card.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: TwinceColors.cyan.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  plan.typeLabel,
                  style: const TextStyle(color: TwinceColors.cyan),
                ),
                const SizedBox(height: 4),
                Text(
                  '${plan.tasks.length} tasks',
                  style: const TextStyle(color: TwinceColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanDetailPage extends StatelessWidget {
  const _PlanDetailPage({
    required this.plan,
    required this.repository,
    required this.evenWeek,
  });

  final ImportedPlan plan;
  final PlanRepository repository;
  final bool evenWeek;

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete plan?'),
          content: Text('This removes the alarms imported from ${plan.title}.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    await repository.deletePlan(plan.sourcePlanId);
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TwinceBackground(
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(
                      plan.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Delete plan',
                    onPressed: () => _delete(context),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: TwinceColors.muted,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    plan.typeLabel,
                    style: const TextStyle(color: TwinceColors.cyan),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    for (final task in plan.tasks)
                      _TaskRow(task: task, evenWeek: evenWeek),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.evenWeek});

  final ImportedTask task;
  final bool evenWeek;

  @override
  Widget build(BuildContext context) {
    final days = repeatLabel(task.repeatDays);
    final recurrence = recurrenceOf(task.weekTags);
    final eligible =
        recurrence != null && recurrenceEligible(recurrence, evenWeek);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101426),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TwinceColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.timeText,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w300),
          ),
          const SizedBox(height: 4),
          Text(task.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (task.description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              task.description,
              style: const TextStyle(color: TwinceColors.muted),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '$days · ${task.weekText} · ${task.enabled ? 'On' : 'Off'} · ${eligible ? 'This week' : 'Not this week'}',
            style: const TextStyle(color: TwinceColors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _PlanImportPage extends StatefulWidget {
  const _PlanImportPage({required this.repository});

  final PlanRepository repository;

  @override
  State<_PlanImportPage> createState() => _PlanImportPageState();
}

class _PlanImportPageState extends State<_PlanImportPage> {
  final _input = TextEditingController();
  String? _error;
  ImportPreview? _preview;
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || data?.text == null) return;
    setState(() {
      _input.text = data!.text!;
      _error = null;
      _preview = null;
    });
  }

  void _parse() {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = widget.repository.preview(_input.text);
      setState(() {
        _preview = preview;
        _busy = false;
      });
    } on PlanImportException catch (error) {
      setState(() {
        _error = error.message;
        _preview = null;
        _busy = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Invalid JSON.';
        _preview = null;
        _busy = false;
      });
    }
  }

  Future<void> _confirm() async {
    final preview = _preview;
    if (preview == null || _busy) return;
    if (preview.updated > 0 || preview.removed > 0) {
      final agreed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Update imported plan?'),
            content: Text(
              '${preview.updated} alarms will be updated and ${preview.removed} will be removed. '
              'Other alarms stay unchanged.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Update'),
              ),
            ],
          );
        },
      );
      if (agreed != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.commit(preview);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Plan imported')));
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is PlanImportException
            ? error.message
            : 'Could not save the plan.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TwinceBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Cancel',
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                  const Expanded(
                    child: Text(
                      'Import Plan',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _paste,
                    child: const Text('Paste'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _input.clear();
                            _error = null;
                            _preview = null;
                          }),
                    child: const Text('Clear'),
                  ),
                ],
              ),
              TextField(
                controller: _input,
                minLines: 8,
                maxLines: 14,
                style: const TextStyle(color: TwinceColors.text, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Paste Twince Export JSON',
                  hintStyle: const TextStyle(color: TwinceColors.muted),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: TwinceColors.stroke),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: TwinceColors.cyan),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Color(0xFFFF8AA0))),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : _parse,
                child: Text(_busy && preview == null ? 'Checking…' : 'Import'),
              ),
              if (preview != null) ...[
                const SizedBox(height: 16),
                Text(
                  preview.plan.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  preview.plan.typeLabel,
                  style: const TextStyle(color: TwinceColors.cyan),
                ),
                Text(
                  '${preview.created} new · ${preview.updated} updated · ${preview.removed} removed',
                  style: const TextStyle(color: TwinceColors.muted),
                ),
                const SizedBox(height: 8),
                for (final task in preview.plan.tasks)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(task.title),
                    subtitle: Text(
                      '${task.timeText} · ${repeatLabel(task.repeatDays)} · ${task.weekText}',
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : _confirm,
                  child: Text(_busy ? 'Saving…' : 'Confirm'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
