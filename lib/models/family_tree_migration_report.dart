/// Summary of how complete a legacy dataset is for the V2 family-tree model.
class FamilyTreeMigrationReport {
  const FamilyTreeMigrationReport({
    required this.totalLegacyMembers,
    required this.totalPersonsProduced,
    required this.totalFamilyUnitsProduced,
    required this.membersMissingMotherId,
    required this.membersMissingSpouseData,
    required this.inferredFamilyUnits,
    required this.explicitFamilyUnits,
    required this.notes,
  });

  final int totalLegacyMembers;
  final int totalPersonsProduced;
  final int totalFamilyUnitsProduced;
  final int membersMissingMotherId;
  final int membersMissingSpouseData;
  final int inferredFamilyUnits;
  final int explicitFamilyUnits;
  final List<String> notes;

  bool get requiresDataUpgrade =>
      membersMissingMotherId > 0 || membersMissingSpouseData > 0;
}
