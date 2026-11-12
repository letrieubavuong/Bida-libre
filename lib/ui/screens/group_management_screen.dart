import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../state/notebook_controller.dart';

/// Màn hình quản lý nhóm biên tập cho từng loại bài (Phase 4B).
class GroupManagementScreen extends StatefulWidget {
  final NotebookController controller;
  final ArticleKind kind;

  const GroupManagementScreen({
    super.key,
    required this.controller,
    required this.kind,
  });

  @override
  State<GroupManagementScreen> createState() => _GroupManagementScreenState();
}

class _GroupManagementScreenState extends State<GroupManagementScreen> {
  Future<void> _showGroupNameDialog({EditorialGroup? existing}) async {
    final result = await showDialog<({String name, String description})>(
      context: context,
      builder: (_) => _GroupNameDialog(existing: existing),
    );
    if (result == null || !mounted) return;

    final err = await widget.controller.saveGroup(
      id: existing?.id,
      kind: widget.kind,
      name: result.name,
      description: result.description,
    );
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _moveGroup(
    List<EditorialGroup> groups,
    int index,
    int delta,
  ) async {
    final next = index + delta;
    if (next < 0 || next >= groups.length) return;
    final ids = groups.map((g) => g.id).toList();
    final item = ids.removeAt(index);
    ids.insert(next, item);
    final err = await widget.controller.reorderGroups(widget.kind, ids);
    if (!mounted || err == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  Future<void> _confirmDeleteGroup(
    EditorialGroup group,
    List<EditorialGroup> allGroups,
  ) async {
    final affectedCount = widget.controller.countArticlesInGroup(group.id);
    final candidates =
        allGroups.where((g) => g.id != group.id).toList(growable: false);
    if (candidates.isEmpty) return;

    final defaultTarget = candidates.firstWhere(
      (g) => DefaultEditorialGroups.isUnclassifiedGroupId(g.id),
      orElse: () => candidates.first,
    );
    var selectedTargetId = defaultTarget.id;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Xóa nhóm "${group.name}"?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                affectedCount > 0
                    ? 'Có $affectedCount bài viết đang thuộc nhóm này. '
                        'Vui lòng chọn nhóm nhận bài trước khi xóa:'
                    : 'Nhóm này chưa có bài viết nào. Chọn nhóm đích mặc định:',
              ),
              const SizedBox(height: 12.0),
              DropdownButtonFormField<String>(
                key: const Key('delete_group_target_dropdown'),
                isExpanded: true,
                initialValue: selectedTargetId,
                decoration: const InputDecoration(
                  labelText: 'Chuyển bài sang nhóm',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: candidates
                    .map(
                      (g) => DropdownMenuItem(
                        value: g.id,
                        child: Text(
                          g.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() => selectedTargetId = val);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              key: const Key('confirm_delete_group_button'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Xóa nhóm'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    final err = await widget.controller.deleteGroup(
      groupId: group.id,
      targetGroupId: selectedTargetId,
    );
    if (!mounted || err == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final groups = widget.controller.groupsForKind(widget.kind);
        final busy = widget.controller.isSaving;
        return Scaffold(
          appBar: AppBar(
            title: Text('Nhóm — ${widget.kind.label}'),
            actions: [
              IconButton(
                key: const Key('add_group_button'),
                tooltip: 'Tạo nhóm mới',
                icon: const Icon(Icons.add),
                onPressed: busy ? null : () => _showGroupNameDialog(),
              ),
            ],
          ),
          body: ListView.builder(
            padding: const EdgeInsets.all(12.0),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final g = groups[index];
              final isUnc =
                  DefaultEditorialGroups.isUnclassifiedGroupId(g.id);
              final count = widget.controller.countArticlesInGroup(g.id);
              return Card(
                key: Key('group_card_${g.id}'),
                child: ListTile(
                  title: Text(
                    g.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    isUnc
                        ? '$count bài • Nhóm mặc định (không thể xóa)'
                        : '$count bài${g.description.isNotEmpty ? ' • ${g.description}' : ''}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: Key('group_up_${g.id}'),
                        tooltip: 'Đưa lên',
                        icon: const Icon(Icons.arrow_upward),
                        onPressed:
                            (busy || index == 0) ? null : () => _moveGroup(groups, index, -1),
                      ),
                      IconButton(
                        key: Key('group_down_${g.id}'),
                        tooltip: 'Đưa xuống',
                        icon: const Icon(Icons.arrow_downward),
                        onPressed: (busy || index == groups.length - 1)
                            ? null
                            : () => _moveGroup(groups, index, 1),
                      ),
                      IconButton(
                        key: Key('rename_group_${g.id}'),
                        tooltip: 'Đổi tên',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed:
                            busy ? null : () => _showGroupNameDialog(existing: g),
                      ),
                      IconButton(
                        key: Key('delete_group_${g.id}'),
                        tooltip: isUnc ? 'Không thể xóa nhóm mặc định' : 'Xóa nhóm',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: (busy || isUnc)
                            ? null
                            : () => _confirmDeleteGroup(g, groups),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _GroupNameDialog extends StatefulWidget {
  final EditorialGroup? existing;

  const _GroupNameDialog({this.existing});

  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _descCtrl = TextEditingController(text: widget.existing?.description ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Tạo nhóm mới' : 'Đổi tên nhóm'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('group_name_input'),
            controller: _nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Tên nhóm *',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10.0),
          TextField(
            key: const Key('group_desc_input'),
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: 'Mô tả ngắn (tùy chọn)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const Key('confirm_save_group_button'),
          onPressed: () => Navigator.of(context).pop(
            (name: _nameCtrl.text, description: _descCtrl.text),
          ),
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}

