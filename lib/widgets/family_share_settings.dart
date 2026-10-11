import 'package:flutter/material.dart';
import '../services/family_profile_service.dart';
import '../services/logout_coordinator.dart';

class FamilyShareSettings extends StatefulWidget {
  const FamilyShareSettings({
    super.key,
    required this.viewer,
    required this.service,
  });
  final String viewer;
  final FamilyProfileService service;
  @override
  State<FamilyShareSettings> createState() => _FamilyShareSettingsState();
}

class _FamilyShareSettingsState extends State<FamilyShareSettings> {
  late final int _token;
  late final String? _owner;
  Map<String, bool> _consent = FamilyProfileService.choices(
    null,
    FamilyProfileService.fields.keys,
  );
  Map<String, bool> _records = FamilyProfileService.choices(
    null,
    FamilyProfileService.recordFields.keys,
  );
  bool _loading = true;
  bool _saving = false;
  bool _loadFailed = false;
  String? _error;
  String? _inviteId;
  bool get _active =>
      mounted &&
      _owner == widget.service.session.currentUid() &&
      widget.service.session.isCurrent(_token);

  @override
  void initState() {
    super.initState();
    _token = widget.service.session.generation;
    _owner = widget.service.session.currentUid();
    widget.service.session.phase.addListener(_sessionChanged);
    _load();
  }

  void _sessionChanged() {
    if (!_active && mounted) {
      setState(() {
        _consent = FamilyProfileService.choices(
          null,
          FamilyProfileService.fields.keys,
        );
        _records = FamilyProfileService.choices(
          null,
          FamilyProfileService.recordFields.keys,
        );
        _error = '帳號已變更，請關閉後重新開啟設定。';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    widget.service.session.phase.removeListener(_sessionChanged);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.service.loadSettings(widget.viewer);
      if (!_active) return;
      setState(() {
        _inviteId = data['inviteId'] is String
            ? data['inviteId'] as String
            : null;
        _consent = FamilyProfileService.choices(data['consent'], _consent.keys);
        _records = FamilyProfileService.choices(data['records'], _records.keys);
        if (_inviteId == null) {
          _loadFailed = true;
          _error = '無法確認家庭關係版本，請重新載入或重新綁定。';
        }
        _loading = false;
      });
    } on SessionOperationCancelled {
      if (!mounted) return;
      if (!_active) {
        _sessionChanged();
      } else {
        setState(() {
          _loadFailed = true;
          _loading = false;
          _error = '載入已取消，未變更分享設定。';
        });
      }
    } catch (_) {
      if (_active) {
        setState(() {
          _error = '無法載入分享設定，未儲存任何變更。';
          _loadFailed = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_active || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.save(
        widget.viewer,
        _consent,
        _records,
        expectedInviteId: _inviteId,
      );
      if (!mounted || !_active) return;
      Navigator.of(context).pop(true);
    } on SessionOperationCancelled {
      if (mounted) setState(() => _error = '帳號已變更，未確認儲存成功。');
    } catch (_) {
      if (_active) setState(() => _error = '儲存失敗，原有授權仍有效；請重試。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('我分享給這位家人的資訊', style: TextStyle(fontSize: 18)),
          const Text(
            '預設全部關閉。姓名與 email 也可不分享，仍可綁定及聊天。'
            '個人資料分享為儲存當下的副本；修改後可在此重新儲存更新。'
            '取消勾選後請儲存撤回；已被對方看過或保存的內容無法收回。',
          ),
          if (_loading)
            const CircularProgressIndicator()
          else ...[
            ...FamilyProfileService.fields.entries.map(
              (entry) => CheckboxListTile(
                title: Text(entry.value),
                value: _consent[entry.key] == true,
                onChanged: !_active || _saving || _loadFailed
                    ? null
                    : (value) =>
                          setState(() => _consent[entry.key] = value == true),
              ),
            ),
            ...FamilyProfileService.recordFields.entries.map(
              (entry) => CheckboxListTile(
                title: Text(entry.value),
                value: _records[entry.key] == true,
                onChanged: !_active || _saving || _loadFailed
                    ? null
                    : (value) =>
                          setState(() => _records[entry.key] = value == true),
              ),
            ),
          ],
          if (_error != null) Text(_error!),
          ElevatedButton(
            onPressed: _active && !_loading && !_saving && !_loadFailed
                ? _save
                : null,
            child: Text(_saving ? '儲存中…' : '儲存分享設定'),
          ),
        ],
      ),
    ),
  );
}
