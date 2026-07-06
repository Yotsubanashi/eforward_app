import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'package:eforward_app/widgets/eforward_app_bar.dart';

class ExcelFileViewerPage extends StatefulWidget {
  final String filePath;
  final String fileName;
  const ExcelFileViewerPage({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<ExcelFileViewerPage> createState() => _ExcelFileViewerPageState();
}

class _ExcelFileViewerPageState extends State<ExcelFileViewerPage> {
  bool _isLoading = true;
  String? _error;
  List<String> _sheetNames = [];
  final Map<String, List<List<String>>> _sheetRows = {};
  int _sheetIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadWorkbook();
  }

  Future<void> _loadWorkbook() async {
    try {
      late Uint8List bytes;
      if (widget.filePath.startsWith('http')) {
        final response = await http.get(Uri.parse(widget.filePath));
        if (response.statusCode != 200) throw Exception('Failed to fetch');
        bytes = response.bodyBytes;
      } else {
        final file = File(widget.filePath);
        if (!await file.exists()) {
          setState(() {
            _error = 'File not found.';
            _isLoading = false;
          });
          return;
        }
        bytes = await file.readAsBytes();
      }

      final decoder = SpreadsheetDecoder.decodeBytes(bytes);
      final names = decoder.tables.keys.toList();
      final parsed = <String, List<List<String>>>{};
      for (final name in names) {
        final table = decoder.tables[name]!;
        final rows = <List<String>>[];
        for (var r = 0; r < table.maxRows; r++) {
          final row = <String>[];
          for (var c = 0; c < table.maxCols; c++) {
            row.add(table.rows[r][c]?.toString() ?? '');
          }
          rows.add(row);
        }
        parsed[name] = rows;
      }

      if (!mounted) return;
      setState(() {
        _sheetNames = names;
        _sheetRows
          ..clear()
          ..addAll(parsed);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to read Excel file: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSheet = _sheetNames.isNotEmpty ? _sheetNames[_sheetIndex] : '';
    final rows = _sheetRows[currentSheet] ?? const <List<String>>[];
    final maxCols = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);

    return Scaffold(
      appBar: EForwardAppBar(
        title: widget.fileName,
        backgroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _sheetNames.isEmpty
          ? const Center(child: Text('No sheets found.'))
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  color: const Color(0xFFF8F8F8),
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: _sheetIndex,
                    items: List.generate(
                      _sheetNames.length,
                      (i) => DropdownMenuItem(
                        value: i,
                        child: Text(_sheetNames[i]),
                      ),
                    ),
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() => _sheetIndex = val);
                    },
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: (maxCols * 140).toDouble().clamp(280, 5000),
                      child: ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, rowIndex) {
                          final row = rows[rowIndex];
                          return Container(
                            color: rowIndex == 0
                                ? const Color(0xFFF1F1F1)
                                : Colors.white,
                            child: Row(
                              children: List.generate(maxCols, (colIndex) {
                                final text = colIndex < row.length
                                    ? row[colIndex]
                                    : '';
                                return Container(
                                  width: 140,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: const Color(0xFFE3E3E3),
                                    ),
                                  ),
                                  child: Text(
                                    text,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: rowIndex == 0
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                );
                              }),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
