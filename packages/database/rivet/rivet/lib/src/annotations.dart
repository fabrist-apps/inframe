// Public usage is documented in the package README; these fields mirror the declaration syntax.
// ignore_for_file: public_member_api_docs

/// Marks a table declaration for Rivet generation.
final class RivetTable {
  const RivetTable({this.name, this.schema, this.renamedFrom, this.rowName});

  final String? name;
  final String? schema;
  final String? renamedFrom;
  final String? rowName;
}

/// Marks an application database declaration for Rivet generation.
final class RivetDatabase {
  const RivetDatabase({required this.name, required this.tables});

  final String name;
  final List<Type> tables;
}

/// Marks a PostgreSQL enum declaration for Rivet generation.
final class RivetEnum {
  const RivetEnum({this.name, this.schema, this.renamedFrom});

  final String? name;
  final String? schema;
  final String? renamedFrom;
}

/// Overrides the stored label and rename hint for an enum value.
final class RivetEnumValue {
  const RivetEnumValue({this.name, this.renamedFrom});

  final String? name;
  final String? renamedFrom;
}
