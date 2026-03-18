import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/family_graph.dart';
import '../models/family_graph_selection.dart';
import '../models/family_unit.dart';
import '../models/person.dart';
import '../services/family_graph_builder.dart';
import '../services/family_tree_layout_engine.dart';
import '../widgets/family_tree_v2/family_tree_canvas.dart';

/// Standalone V2 page that wires data loading, contextual graph selection,
/// layout, and rendering without touching the legacy tree page.
class FamilyTreeV2Page extends StatefulWidget {
  const FamilyTreeV2Page({
    super.key,
    this.collection = 'members_public',
    this.initialSelectedPersonId,
    this.initialMode = FamilyTreeDisplayMode.focused,
    this.title = 'شجرة العائلة V2',
  });

  final String collection;
  final String? initialSelectedPersonId;
  final FamilyTreeDisplayMode initialMode;
  final String title;

  @override
  State<FamilyTreeV2Page> createState() => _FamilyTreeV2PageState();
}

class _FamilyTreeV2PageState extends State<FamilyTreeV2Page> {
  final FamilyGraphBuilder _graphBuilder = const FamilyGraphBuilder();
  final TextEditingController _searchController = TextEditingController();

  late FamilyTreeDisplayMode _mode;
  String? _selectedPersonId;
  String _searchQuery = '';
  Set<String> _collapsedFamilyUnitIds = <String>{};

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _selectedPersonId = widget.initialSelectedPersonId;
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection(widget.collection).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorState(message: 'تعذر تحميل بيانات شجرة العائلة.');
          }

          final docs = snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final people = docs.map(_personFromDoc).toList(growable: false);
          final familyUnits = _deriveFamilyUnits(docs, people);
          final preferredPersonId = _resolvePreferredPersonId(people);
          _syncCollapsedFamilies(familyUnits);
          final selection = _graphBuilder.buildSelection(
            FamilyGraphBuildRequest(
              persons: people,
              familyUnits: familyUnits,
              focusPersonId: preferredPersonId,
              mode: _mode,
              searchQuery: _searchQuery,
              includeSiblingsForContext: true,
              collapsedFamilyUnitIds: _collapsedFamilyUnitIds,
            ),
          );
          final graph = selection.graph;
          final selectedPersonId = selection.focusPersonId;

          if (graph.persons.isEmpty) {
            return const _EmptyState();
          }

          final allPeople = [...people]
            ..sort((a, b) => a.fullName.compareTo(b.fullName));

          return Column(
            children: <Widget>[
              _ControlPanel(
                mode: _mode,
                selectedPersonId: selectedPersonId,
                people: allPeople,
                searchController: _searchController,
                onModeChanged: (mode) => setState(() {
                  _mode = mode;
                  _collapsedFamilyUnitIds = <String>{};
                }),
                onPersonChanged: (personId) => setState(() => _selectedPersonId = personId),
                searchSummary: _buildSearchSummary(selection),
              ),
              const Divider(height: 1),
              Expanded(
                child: FamilyTreeCanvas(
                  graph: graph,
                  focusPersonId: selectedPersonId,
                  collapsedFamilyUnitIds: _collapsedFamilyUnitIds,
                  onFamilyUnitTap: _toggleFamilyCollapse,
                  layoutConfig: const FamilyTreeLayoutConfig(
                    personNodeSize: Size(182, 112),
                    familyUnitNodeSize: Size(48, 28),
                    spouseGap: 40,
                    siblingGap: 34,
                    familyGap: 68,
                    generationGap: 136,
                    canvasPadding: EdgeInsets.all(72),
                  ),
                  initialScale: 0.95,
                  minScale: 0.32,
                  maxScale: 2.6,
                  onPersonTap: (person) => setState(() => _selectedPersonId = person.id),
                ),
              ),
            ],
          );
        },
      ),
    );
  }


  void _syncCollapsedFamilies(List<FamilyUnit> familyUnits) {
    final validIds = familyUnits.map((unit) => unit.id).toSet();
    _collapsedFamilyUnitIds = _collapsedFamilyUnitIds.intersection(validIds);

    if (_collapsedFamilyUnitIds.isNotEmpty || validIds.isEmpty) {
      return;
    }

    final defaults = <String>{};
    for (final unit in familyUnits) {
      if (unit.childrenIds.isEmpty) {
        continue;
      }
      final shouldCollapse = switch (_mode) {
        FamilyTreeDisplayMode.focused => true,
        FamilyTreeDisplayMode.ancestors => false,
        FamilyTreeDisplayMode.descendants => false,
        FamilyTreeDisplayMode.full => true,
      };
      if (shouldCollapse) {
        defaults.add(unit.id);
      }
    }

    if (_selectedPersonId != null) {
      defaults.removeWhere((unitId) {
        final unit = familyUnits.firstWhere(
          (candidate) => candidate.id == unitId,
          orElse: () => FamilyUnit(id: unitId),
        );
        return unit.husbandId == _selectedPersonId ||
            unit.wifeId == _selectedPersonId ||
            unit.childrenIds.contains(_selectedPersonId);
      });
    }

    _collapsedFamilyUnitIds = defaults;
  }

  void _toggleFamilyCollapse(String familyUnitId) {
    setState(() {
      if (_collapsedFamilyUnitIds.contains(familyUnitId)) {
        _collapsedFamilyUnitIds = <String>{..._collapsedFamilyUnitIds}..remove(familyUnitId);
      } else {
        _collapsedFamilyUnitIds = <String>{..._collapsedFamilyUnitIds, familyUnitId};
      }
    });
  }

  void _handleSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query == _searchQuery) {
      return;
    }

    setState(() => _searchQuery = query);
  }

  Person _personFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final normalized = <String, dynamic>{...data};

    if (!normalized.containsKey('fullName') && normalized.containsKey('name')) {
      normalized['fullName'] = normalized['name'];
    }

    if (!normalized.containsKey('gender') && normalized.containsKey('isFemale')) {
      normalized['gender'] = normalized['isFemale'] == true ? 'female' : 'male';
    }

    return Person.fromMap(doc.id, normalized);
  }

  List<FamilyUnit> _deriveFamilyUnits(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    List<Person> people,
  ) {
    final peopleById = <String, Person>{for (final person in people) person.id: person};
    final rawById = <String, Map<String, dynamic>>{
      for (final doc in docs) doc.id: doc.data(),
    };

    final groupedChildren = <String, _FamilyUnitDraft>{};

    for (final person in people) {
      final key = _familyKey(person.fatherId, person.motherId);
      if (key == null) {
        continue;
      }

      groupedChildren.putIfAbsent(
        key,
        () => _FamilyUnitDraft(
          husbandId: person.fatherId,
          wifeId: person.motherId,
        ),
      ).childrenIds.add(person.id);
    }

    for (final person in people) {
      final raw = rawById[person.id] ?? const <String, dynamic>{};
      final spouseIds = _readSpouseIds(raw);
      for (final spouseId in spouseIds) {
        if (!peopleById.containsKey(spouseId)) {
          continue;
        }

        final husbandId = _pickHusbandId(person.id, spouseId, peopleById);
        final wifeId = husbandId == person.id ? spouseId : person.id;
        final key = _familyKey(husbandId, wifeId)!;
        groupedChildren.putIfAbsent(
          key,
          () => _FamilyUnitDraft(husbandId: husbandId, wifeId: wifeId),
        );
      }
    }

    final result = groupedChildren.entries
        .map(
          (entry) => FamilyUnit(
            id: 'family_${entry.key}',
            husbandId: entry.value.husbandId,
            wifeId: entry.value.wifeId,
            childrenIds: entry.value.childrenIds.toList()..sort(),
          ),
        )
        .where((unit) =>
            unit.husbandId != null || unit.wifeId != null || unit.childrenIds.isNotEmpty)
        .toList(growable: false)
      ..sort((a, b) => a.id.compareTo(b.id));

    return result;
  }

  String? _resolvePreferredPersonId(List<Person> people) {
    if (_selectedPersonId != null && people.any((person) => person.id == _selectedPersonId)) {
      return _selectedPersonId;
    }

    if (widget.initialSelectedPersonId != null &&
        people.any((person) => person.id == widget.initialSelectedPersonId)) {
      _selectedPersonId = widget.initialSelectedPersonId;
      return _selectedPersonId;
    }

    if (people.isEmpty) {
      return null;
    }

    final sorted = [...people]..sort((a, b) => a.fullName.compareTo(b.fullName));
    _selectedPersonId = sorted.first.id;
    return _selectedPersonId;
  }


  String? _buildSearchSummary(FamilyGraphSelection selection) {
    if (!selection.hasQuery) {
      return null;
    }

    if (!selection.hasMatches) {
      return 'لا توجد نتائج مطابقة، تم الإبقاء على الشجرة الحالية سليمة.';
    }

    final count = selection.matchedPersonIds.length;
    final collapsedCount = selection.collapsedFamilyUnitIds.length;
    return 'تم العثور على $count نتيجة مع إبقاء السياق العائلي كاملاً.${collapsedCount > 0 ? ' توجد $collapsedCount عائلات مطوية لتقليل التكدس.' : ''}';
  }

  String? _familyKey(String? fatherId, String? motherId) {
    if (fatherId == null && motherId == null) {
      return null;
    }
    return '${fatherId ?? 'none'}__${motherId ?? 'none'}';
  }

  Set<String> _readSpouseIds(Map<String, dynamic> data) {
    final values = <String>{};
    for (final key in <String>['spouseId', 'husbandId', 'wifeId']) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        values.add(value.toString().trim());
      }
    }

    final spouseList = data['spouseIds'];
    if (spouseList is List) {
      values.addAll(
        spouseList
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty),
      );
    }

    return values;
  }

  String _pickHusbandId(
    String firstPersonId,
    String secondPersonId,
    Map<String, Person> peopleById,
  ) {
    final first = peopleById[firstPersonId];
    final second = peopleById[secondPersonId];

    if (first?.gender == PersonGender.male && second?.gender != PersonGender.male) {
      return firstPersonId;
    }
    if (second?.gender == PersonGender.male && first?.gender != PersonGender.male) {
      return secondPersonId;
    }
    return firstPersonId.compareTo(secondPersonId) <= 0 ? firstPersonId : secondPersonId;
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.mode,
    required this.selectedPersonId,
    required this.people,
    required this.searchController,
    required this.onModeChanged,
    required this.onPersonChanged,
    this.searchSummary,
  });

  final FamilyTreeDisplayMode mode;
  final String? selectedPersonId;
  final List<Person> people;
  final TextEditingController searchController;
  final ValueChanged<FamilyTreeDisplayMode> onModeChanged;
  final ValueChanged<String?> onPersonChanged;
  final String? searchSummary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          children: <Widget>[
            TextField(
              controller: searchController,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'ابحث عن شخص داخل شجرة العائلة',
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            if (searchSummary != null) ...<Widget>[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  searchSummary!,
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: FamilyTreeDisplayMode.values.map((modeOption) {
                return ChoiceChip(
                  label: Text(_modeLabel(modeOption), textDirection: TextDirection.rtl),
                  selected: mode == modeOption,
                  onSelected: (_) => onModeChanged(modeOption),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: people.any((person) => person.id == selectedPersonId)
                  ? selectedPersonId
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'الشخص المحدد',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              items: people
                  .map(
                    (person) => DropdownMenuItem<String>(
                      value: person.id,
                      child: Text(
                        person.fullName,
                        textDirection: RegExp(r'[\u0600-\u06FF]').hasMatch(person.fullName)
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: onPersonChanged,
            ),
          ],
        ),
      ),
    );
  }

  String _modeLabel(FamilyTreeDisplayMode mode) {
    return switch (mode) {
      FamilyTreeDisplayMode.focused => 'مركّز',
      FamilyTreeDisplayMode.ancestors => 'الأصول',
      FamilyTreeDisplayMode.descendants => 'الفروع',
      FamilyTreeDisplayMode.full => 'كامل',
    };
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'لا توجد بيانات متاحة لبناء شجرة العائلة V2 حالياً.',
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
        ),
      ),
    );
  }
}

class _FamilyUnitDraft {
  _FamilyUnitDraft({
    required this.husbandId,
    required this.wifeId,
  });

  final String? husbandId;
  final String? wifeId;
  final Set<String> childrenIds = <String>{};
}
