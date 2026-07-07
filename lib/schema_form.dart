import 'package:flutter/material.dart';

import 'api.dart';

/// Parsed view of the schema form contract (docs/schema-forms.md on the
/// object server). Schemas declare semantics, never widgets — this file maps
/// those semantics onto Scroll's idiom (dropdowns, pickers, switches).

/// Boolean record fields store canonically as "true"/"false" strings; older
/// rows and raw-JSON writes may hold real booleans or other spellings.
bool schemaBoolIsTrue(dynamic value) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  return text == 'true' || text == '1' || text == 'yes';
}

class SchemaFieldSpec {
  SchemaFieldSpec({
    required this.name,
    required this.label,
    required this.type,
    required this.required,
    required this.readOnly,
    required this.enumValues,
    required this.relationCollection,
    required this.relationDisplayField,
    required this.defaultValue,
    required this.placeholder,
    required this.help,
    required this.validation,
    required this.transitions,
  });

  final String name;
  final String label;
  final String type;
  final bool required;
  final bool readOnly;
  final List<String> enumValues;
  final String? relationCollection;
  final String relationDisplayField;
  final dynamic defaultValue;
  final String? placeholder;
  final String? help;
  final Map<String, dynamic> validation;

  /// Enum lifecycle map ({state: [allowed next states]}), enforced on record
  /// update server-side. A value missing from the map is terminal.
  final Map<String, List<String>> transitions;

  bool get isEnum => enumValues.isNotEmpty;
  bool get hasTransitions => transitions.isNotEmpty;

  /// The enum values legal from [current]: the current state plus its
  /// allowed moves. Without a transitions map (or before a value exists,
  /// i.e. on create) every enum value is offered.
  List<String> allowedEnumValues(String? current) {
    if (!hasTransitions || current == null || current.isEmpty) {
      return enumValues;
    }
    final moves = transitions[current] ?? const <String>[];
    return [current, ...moves.where((move) => move != current)];
  }

  bool get isRelation =>
      relationCollection != null && relationCollection!.isNotEmpty;
  bool get isBoolean => type == 'boolean' || type == 'bool';
  bool get isInteger => type == 'integer' || type == 'int';
  bool get isNumber => type == 'number' || type == 'float' || type == 'double';
  bool get isDate => type == 'date';
  bool get isDateTime => type == 'datetime' || type == 'timestamp';
  // 'text' is the plain string type in the schema vocabulary; only
  // 'textarea' asks for a multiline control.
  bool get isMultiline => type == 'textarea';

  static SchemaFieldSpec from(Map<String, dynamic> raw) {
    final name = (raw['name'] ?? raw['field'] ?? '').toString();
    final relation = raw['relation'] ?? raw['references'] ?? raw['ref'];
    String? relationCollection;
    var relationDisplayField = 'name';
    if (relation is String && relation.trim().isNotEmpty) {
      relationCollection = relation.trim();
    } else if (relation is Map) {
      relationCollection = relation['collection']?.toString();
      final display = relation['display_field']?.toString();
      if (display != null && display.isNotEmpty) {
        relationDisplayField = display;
      }
    }
    final enumRaw = raw['enum'] ?? raw['choices'] ?? raw['options'];
    final type = (raw['type'] ?? raw['field_type'] ?? 'string')
        .toString()
        .toLowerCase();
    return SchemaFieldSpec(
      name: name,
      label: (raw['label'] ?? _titleCase(name)).toString(),
      type: type,
      required: raw['required'] == true,
      readOnly:
          raw['read_only'] == true ||
          raw['readonly'] == true ||
          raw['computed'] == true ||
          type == 'computed',
      enumValues: enumRaw is List
          ? enumRaw.map((value) => value.toString()).toList()
          : const [],
      relationCollection: relationCollection,
      relationDisplayField: relationDisplayField,
      defaultValue: raw['default'],
      placeholder: raw['placeholder']?.toString(),
      help: (raw['help'] ?? raw['description'])?.toString(),
      validation: raw['validation'] is Map
          ? Map<String, dynamic>.from(raw['validation'] as Map)
          : const {},
      transitions: raw['transitions'] is Map
          ? (raw['transitions'] as Map).map(
              (state, moves) => MapEntry(
                state.toString(),
                moves is List
                    ? moves.map((move) => move.toString()).toList()
                    : const <String>[],
              ),
            )
          : const {},
    );
  }

  static String _titleCase(String value) {
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}

class SchemaFormSpec {
  SchemaFormSpec({
    required this.fields,
    required this.listMode,
    required this.listFields,
  });

  final List<SchemaFieldSpec> fields;
  final String listMode; // table | cards | feed
  final List<String> listFields;

  bool get hasFields => fields.isNotEmpty;

  static final SchemaFormSpec empty = SchemaFormSpec(
    fields: const [],
    listMode: 'table',
    listFields: const [],
  );

  /// Accepts either the schema document itself or a detail payload that
  /// nests it under `schema`.
  static SchemaFormSpec fromSchema(Map<String, dynamic>? detail) {
    if (detail == null) return empty;
    final schema = detail['schema'] is Map
        ? Map<String, dynamic>.from(detail['schema'] as Map)
        : detail;

    final rawFields = schema['fields'];
    final specs = <SchemaFieldSpec>[];
    if (rawFields is List) {
      for (final item in rawFields) {
        if (item is Map) {
          final spec = SchemaFieldSpec.from(Map<String, dynamic>.from(item));
          if (spec.name.isNotEmpty) specs.add(spec);
        }
      }
    } else if (rawFields is Map) {
      rawFields.forEach((key, value) {
        final map = value is Map
            ? Map<String, dynamic>.from(value)
            : <String, dynamic>{};
        map['name'] = key.toString();
        final spec = SchemaFieldSpec.from(map);
        if (spec.name.isNotEmpty) specs.add(spec);
      });
    }

    // forms.default.fields declares operator-chosen field order.
    final forms = schema['forms'];
    if (forms is Map && forms['default'] is Map) {
      final order = (forms['default'] as Map)['fields'];
      if (order is List && order.isNotEmpty) {
        final rank = <String, int>{
          for (var i = 0; i < order.length; i++) order[i].toString(): i,
        };
        specs.sort((a, b) {
          final ra = rank[a.name] ?? (rank.length + specs.indexOf(a));
          final rb = rank[b.name] ?? (rank.length + specs.indexOf(b));
          return ra.compareTo(rb);
        });
      }
    }

    var listMode = 'table';
    var listFields = const <String>[];
    final views = schema['views'];
    if (views is Map) {
      final mode = views['list_mode']?.toString();
      if (mode != null && mode.isNotEmpty) listMode = mode;
      final fields = views['list_fields'];
      if (fields is List) {
        listFields = fields.map((f) => f.toString()).toList();
      }
    }

    return SchemaFormSpec(
      fields: specs,
      listMode: listMode,
      listFields: listFields,
    );
  }
}

/// Sentinel returned when the operator asks to edit the record as raw JSON
/// instead of through the generated form.
const schemaFormRawJsonRequested = '__schema_form_raw_json__';

/// Shows a form generated from [spec]. Returns the record payload to write,
/// [schemaFormRawJsonRequested] if the operator wants the raw JSON editor,
/// or null on cancel.
Future<dynamic> showSchemaRecordFormDialog(
  BuildContext context, {
  required String collection,
  required SchemaFormSpec spec,
  Map<String, dynamic>? initial,
}) {
  return showDialog<dynamic>(
    context: context,
    builder: (dialogContext) => _SchemaRecordFormDialog(
      collection: collection,
      spec: spec,
      initial: initial,
    ),
  );
}

class _SchemaRecordFormDialog extends StatefulWidget {
  const _SchemaRecordFormDialog({
    required this.collection,
    required this.spec,
    this.initial,
  });

  final String collection;
  final SchemaFormSpec spec;
  final Map<String, dynamic>? initial;

  @override
  State<_SchemaRecordFormDialog> createState() =>
      _SchemaRecordFormDialogState();
}

class _SchemaRecordFormDialogState extends State<_SchemaRecordFormDialog> {
  final Map<String, TextEditingController> _text = {};
  final Map<String, String?> _enums = {};
  final Map<String, String?> _relations = {};
  final Map<String, bool> _booleans = {};
  final Map<String, String> _fieldErrors = {};
  final Map<String, List<Map<String, dynamic>>> _relationOptions = {};
  final Set<String> _relationsLoading = {};
  final ScrollController _scrollController = ScrollController();

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    for (final field in widget.spec.fields) {
      if (field.readOnly) continue;
      var initial = widget.initial?[field.name] ?? field.defaultValue;
      // Owner-scoped app collections require owner_id == session user on
      // create; prefill it so the server-enforced value is the starting one.
      if (!_isEdit && initial == null && field.name == 'owner_id') {
        initial = ScrollAPI().sessionUserId;
      }
      if (field.isBoolean) {
        _booleans[field.name] = schemaBoolIsTrue(initial);
      } else if (field.isEnum) {
        final value = initial?.toString();
        _enums[field.name] = field.enumValues.contains(value) ? value : null;
      } else if (field.isRelation) {
        _relations[field.name] = initial?.toString();
        _loadRelationOptions(field);
      } else {
        _text[field.name] = TextEditingController(
          text: initial?.toString() ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _text.values) {
      controller.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadRelationOptions(SchemaFieldSpec field) async {
    final collection = field.relationCollection;
    if (collection == null || _relationsLoading.contains(field.name)) return;
    _relationsLoading.add(field.name);
    final records = await ScrollAPI().listAdminCollectionRecords(
      collection,
      limit: 100,
    );
    if (!mounted) return;
    setState(() {
      _relationOptions[field.name] = [
        for (final record in records)
          if (record is Map)
            Map<String, dynamic>.from(
              record.map((k, v) => MapEntry(k.toString(), v)),
            ),
      ];
    });
  }

  String _relationLabel(SchemaFieldSpec field, Map<String, dynamic> record) {
    final display = record[field.relationDisplayField];
    final id = _recordId(record);
    if (display != null && display.toString().trim().isNotEmpty) {
      return '${display.toString()} ($id)';
    }
    return id;
  }

  String _recordId(Map<String, dynamic> record) {
    final raw =
        record['id'] ?? record['record_id'] ?? record['key'] ?? record['name'];
    return raw?.toString() ?? '';
  }

  Map<String, dynamic>? _buildPayload() {
    final payload = <String, dynamic>{};
    final errors = <String, String>{};
    for (final field in widget.spec.fields) {
      if (field.readOnly) continue;
      dynamic value;
      if (field.isBoolean) {
        // Booleans store canonically as "true"/"false" strings server-side.
        value = (_booleans[field.name] ?? false) ? 'true' : 'false';
      } else if (field.isEnum) {
        value = _enums[field.name];
      } else if (field.isRelation) {
        value = _relations[field.name];
      } else {
        final text = _text[field.name]?.text.trim() ?? '';
        if (text.isEmpty) {
          value = null;
        } else if (field.isInteger) {
          value = int.tryParse(text);
          if (value == null) errors[field.name] = 'Must be an integer';
        } else if (field.isNumber) {
          value = num.tryParse(text);
          if (value == null) errors[field.name] = 'Must be a number';
        } else {
          value = text;
        }
      }

      final missing =
          value == null || (value is String && value.trim().isEmpty);
      if (field.required && missing && !errors.containsKey(field.name)) {
        errors[field.name] = 'Required';
      }

      if (!missing) {
        payload[field.name] = value;
      } else if (_isEdit && widget.initial!.containsKey(field.name)) {
        // Cleared on edit — send an explicit null so the server clears it.
        payload[field.name] = null;
      }
    }
    if (errors.isNotEmpty) {
      setState(() {
        _fieldErrors
          ..clear()
          ..addAll(errors);
      });
      return null;
    }
    return payload;
  }

  Future<void> _pickDate(SchemaFieldSpec field) async {
    final controller = _text[field.name];
    if (controller == null) return;
    final now = DateTime.now();
    final current = DateTime.tryParse(controller.text) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 20),
    );
    if (picked == null) return;
    controller.text = field.isDateTime
        ? picked.toUtc().toIso8601String()
        : '${picked.year.toString().padLeft(4, '0')}-'
              '${picked.month.toString().padLeft(2, '0')}-'
              '${picked.day.toString().padLeft(2, '0')}';
  }

  Widget _buildField(SchemaFieldSpec field) {
    final error = _fieldErrors[field.name];
    final label = field.required ? '${field.label} *' : field.label;

    if (field.readOnly) {
      final value = widget.initial?[field.name];
      if (value == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InputDecorator(
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: '${field.label} (read only)',
            isDense: true,
          ),
          child: Text(value.toString(), style: const TextStyle(fontSize: 13)),
        ),
      );
    }

    if (field.isBoolean) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(label, style: const TextStyle(fontSize: 13)),
          subtitle: field.help == null
              ? null
              : Text(field.help!, style: const TextStyle(fontSize: 11)),
          value: _booleans[field.name] ?? false,
          onChanged: (value) => setState(() => _booleans[field.name] = value),
        ),
      );
    }

    if (field.isEnum) {
      // With a transitions map, edits may only move from the record's
      // stored state to its allowed next states (server-enforced).
      final storedState = _isEdit
          ? widget.initial![field.name]?.toString()
          : null;
      final values = field.allowedEnumValues(storedState);
      final terminal =
          field.hasTransitions && storedState != null && values.length == 1;
      var helper = field.help;
      if (terminal) {
        helper = '"$storedState" is a terminal state';
      } else if (field.hasTransitions && storedState != null) {
        helper = helper ?? 'Allowed moves from "$storedState"';
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: _enums[field.name],
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: label,
            helperText: helper,
            errorText: error,
            isDense: true,
          ),
          items: [
            if (!field.required)
              const DropdownMenuItem<String>(
                value: null,
                child: Text('—', style: TextStyle(color: Colors.white38)),
              ),
            ...values.map(
              (value) =>
                  DropdownMenuItem<String>(value: value, child: Text(value)),
            ),
          ],
          onChanged: terminal
              ? null
              : (value) => setState(() => _enums[field.name] = value),
        ),
      );
    }

    if (field.isRelation) {
      final options = _relationOptions[field.name];
      final selected = _relations[field.name];
      final knownIds = options?.map(_recordId).toSet() ?? const <String>{};
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: knownIds.contains(selected) ? selected : null,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: label,
            helperText:
                field.help ??
                'References ${field.relationCollection} records'
                    '${options == null ? ' (loading…)' : ''}',
            errorText: error,
            isDense: true,
          ),
          items: [
            if (!field.required)
              const DropdownMenuItem<String>(
                value: null,
                child: Text('—', style: TextStyle(color: Colors.white38)),
              ),
            ...?options?.map(
              (record) => DropdownMenuItem<String>(
                value: _recordId(record),
                child: Text(
                  _relationLabel(field, record),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: (value) => setState(() => _relations[field.name] = value),
        ),
      );
    }

    final controller = _text[field.name];
    final maxLength = (field.validation['max_length'] as num?)?.toInt();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: field.isMultiline ? 4 : 1,
        maxLength: maxLength,
        keyboardType: field.isInteger || field.isNumber
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: label,
          hintText: field.placeholder,
          helperText: field.help,
          errorText: error,
          isDense: true,
          counterText: maxLength == null ? null : '',
          suffixIcon: field.isDate || field.isDateTime
              ? IconButton(
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  onPressed: () => _pickDate(field),
                )
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEdit
            ? 'Edit ${widget.collection} record'
            : 'New ${widget.collection} record',
      ),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.spec.fields.map(_buildField).toList(),
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(schemaFormRawJsonRequested),
          child: const Text('Edit as JSON'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () {
            final payload = _buildPayload();
            if (payload != null) Navigator.of(context).pop(payload);
          },
          icon: const Icon(Icons.save_outlined, size: 16),
          label: Text(_isEdit ? 'Save Record' : 'Create Record'),
        ),
      ],
    );
  }
}
