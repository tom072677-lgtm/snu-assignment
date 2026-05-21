import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/map_repository.dart';
import '../../domain/favorite_place.dart';

class PlaceSearchSheet extends ConsumerStatefulWidget {
  final String title;
  final String? fixedName; // null → 사용자가 이름 직접 입력
  final Set<String> existingNames;
  final void Function(FavoritePlace) onSave;

  const PlaceSearchSheet({
    super.key,
    required this.title,
    required this.fixedName,
    required this.onSave,
    this.existingNames = const {},
  });

  @override
  ConsumerState<PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends ConsumerState<PlaceSearchSheet> {
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  List<PlaceResult> _results = [];
  PlaceResult? _selected;

  @override
  void initState() {
    super.initState();
    if (widget.fixedName != null) _nameCtrl.text = widget.fixedName!;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    try {
      const snuLat = 37.4607;
      const snuLng = 126.9526;
      final results =
          await ref.read(mapRepositoryProvider).searchPlace(q, snuLat, snuLng);
      setState(() => _results = results.take(5).toList());
    } catch (_) {
      setState(() => _results = []);
    }
  }

  bool get _canSave {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _selected == null) return false;
    if (widget.fixedName == null && widget.existingNames.contains(name)) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (widget.fixedName == null) ...[
                TextField(
                  controller: _nameCtrl,
                  maxLength: 10,
                  decoration: const InputDecoration(
                    labelText: '이름',
                    hintText: '예: 과방, 도서관',
                    border: OutlineInputBorder(),
                    isDense: true,
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  labelText: '위치 검색',
                  hintText: '장소명 입력',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: _search,
              ),
              if (_selected != null) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(_selected!.name,
                        style:
                            const TextStyle(fontSize: 13, color: Colors.green),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ],
              if (_results.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: _results.map((p) {
                      return ListTile(
                        dense: true,
                        title: Text(p.name,
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(p.address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11)),
                        onTap: () {
                          _searchCtrl.text = p.name;
                          setState(() {
                            _selected = p;
                            _results = [];
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _canSave
                    ? () {
                        widget.onSave(FavoritePlace(
                          name: _nameCtrl.text.trim(),
                          lat: _selected!.lat,
                          lng: _selected!.lng,
                        ));
                        Navigator.pop(context);
                      }
                    : null,
                child: const Text('저장'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
