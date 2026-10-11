import 'prescription_model.dart';

/// Source belongs to an entry, never to its mutable position in the list.
class PrescriptionDraftEntry {
  PrescriptionDraftEntry(this.medicine, this.source);
  PrescriptionMedicine medicine;
  String? source;
}

class PrescriptionDraft {
  PrescriptionDraft(List<PrescriptionMedicine> medicines, {String? source})
    : entries = medicines
          .map((m) => PrescriptionDraftEntry(m, source))
          .toList();
  final List<PrescriptionDraftEntry> entries;
  List<PrescriptionMedicine> get medicines =>
      entries.map((e) => e.medicine).toList();
  Map<int, String> get sources => {
    for (var i = 0; i < entries.length; i++)
      if (entries[i].source != null) i: entries[i].source!,
  };
  void remove(PrescriptionDraftEntry entry) => entries.remove(entry);
  void update(
    PrescriptionDraftEntry entry,
    PrescriptionMedicine medicine,
    String? source,
  ) {
    if (!entries.contains(entry)) return;
    entry.medicine = medicine;
    entry.source = source;
  }
}
