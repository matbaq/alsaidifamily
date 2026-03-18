class FamilyUnit {
  const FamilyUnit({
    required this.id,
    this.husbandId,
    this.wifeId,
    this.childrenIds = const <String>[],
  });

  final String id;
  final String? husbandId;
  final String? wifeId;
  final List<String> childrenIds;

  bool get hasCouple => husbandId != null && wifeId != null;
  bool get isSingleParentFamily =>
      (husbandId != null && wifeId == null) ||
      (husbandId == null && wifeId != null);

  FamilyUnit copyWith({
    String? id,
    String? husbandId,
    String? wifeId,
    List<String>? childrenIds,
    bool clearHusbandId = false,
    bool clearWifeId = false,
  }) {
    return FamilyUnit(
      id: id ?? this.id,
      husbandId: clearHusbandId ? null : (husbandId ?? this.husbandId),
      wifeId: clearWifeId ? null : (wifeId ?? this.wifeId),
      childrenIds: List.unmodifiable(childrenIds ?? this.childrenIds),
    );
  }

  factory FamilyUnit.fromMap(String id, Map<String, dynamic> map) {
    return FamilyUnit(
      id: id,
      husbandId: _readNullableString(map['husbandId']),
      wifeId: _readNullableString(map['wifeId']),
      childrenIds: List.unmodifiable(
        (map['childrenIds'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty),
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'husbandId': husbandId,
      'wifeId': wifeId,
      'childrenIds': childrenIds,
    };
  }

  static String? _readNullableString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
}
