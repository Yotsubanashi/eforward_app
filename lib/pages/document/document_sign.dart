import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class DocumentSignScreen extends StatefulWidget {
  final Map<String, dynamic> document;
  const DocumentSignScreen({super.key, required this.document});

  @override
  State<DocumentSignScreen> createState() => _DocumentSignScreenState();
}

class _DocumentSignScreenState extends State<DocumentSignScreen> {
  bool _isSigning = false;
  bool _signed = false;

  // PDF
  File? _pdfFile;
  bool _pdfLoaded = false;
  int _totalPages = 1;
  int _currentPage = 0;
  PDFViewController? _pdfController;

  // Signature from SharedPreferences
  String _signatureType = '';
  String _signatureText = '';
  String _signatureImagePath = '';
  String? _drawBase64;

  // Draggable signature overlay
  bool _showSignatureOverlay = false;
  Offset _signaturePosition = const Offset(40, 40);
  String _signedTimestamp = '';

  // PDF view key to get dimensions
  final GlobalKey _pdfContainerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadSavedSignature();
  }

  Future<void> _loadSavedSignature() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _signatureType = prefs.getString('signature_type') ?? '';
      _signatureText = prefs.getString('signature_text') ?? '';
      _signatureImagePath = prefs.getString('signature_image_path') ?? '';
      _drawBase64 = prefs.getString('signature_draw_data');
    });
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _pdfFile = File(result.files.single.path!);
        _pdfLoaded = false;
        _showSignatureOverlay = false;
        _signed = false;
      });
    }
  }

  void _onSignDocument() {
    if (_pdfFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please upload a PDF document first."),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
      return;
    }

    if (_signatureType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "No saved signature found. Please create one in the Sign tab.",
          ),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
      return;
    }

    // Generate timestamp in Philippine time (PHT/GMT+8)
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    _signedTimestamp = DateFormat('MMM dd, yyyy · HH:mm').format(now) + ' PHT';

    setState(() => _showSignatureOverlay = true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Drag your signature to position it on the document."),
        backgroundColor: Color(0xFF1A1A1A),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _confirmSign() async {
    setState(() => _isSigning = true);
    await Future.delayed(const Duration(milliseconds: 1200));
    setState(() {
      _isSigning = false;
      _signed = true;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Document signed successfully!"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Widget _buildSignatureWidget({double scale = 1.0}) {
    if (_signatureType == 'draw' && _drawBase64 != null) {
      return Image.memory(
        base64Decode(_drawBase64!),
        width: 140 * scale,
        height: 60 * scale,
        fit: BoxFit.contain,
      );
    } else if (_signatureType == 'type' && _signatureText.isNotEmpty) {
      return Container(
        width: 140 * scale,
        height: 60 * scale,
        alignment: Alignment.center,
        child: Text(
          _signatureText,
          style: TextStyle(
            fontSize: 22 * scale,
            fontStyle: FontStyle.italic,
            color: const Color(0xFF1A1A1A),
            fontWeight: FontWeight.w400,
          ),
        ),
      );
    } else if (_signatureType == 'capture' && _signatureImagePath.isNotEmpty) {
      return Image.file(
        File(_signatureImagePath),
        width: 140 * scale,
        height: 60 * scale,
        fit: BoxFit.contain,
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F5F7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: Color(0xFF1A1A1A),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "DOCUMENT SIGNING",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: Color(0xFF1A1A1A),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: const [
                Icon(Icons.shield_outlined, color: Color(0xFFCC0000), size: 16),
                SizedBox(width: 4),
                Text(
                  "E-FORWARD",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: Color(0xFFCC0000),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Document Info Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE8E8E8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc['id'],
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFCC0000),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    doc['title'],
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: Color(0xFFF0F0F0)),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    Icons.person_outline,
                    "CREATED BY",
                    doc['createdBy'],
                  ),
                  const SizedBox(height: 10),
                  _buildInfoRow(
                    Icons.calendar_today_outlined,
                    "DATE & TIME",
                    doc['dateTime'],
                  ),
                  const SizedBox(height: 10),
                  _buildInfoRow(Icons.label_outline, "CATEGORY", doc['label']),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: Color(0xFFF0F0F0)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        doc['label'],
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.black45,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        "${(doc['progress'] * 100).toInt()}%",
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.black45,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Stack(
                    children: [
                      Container(
                        height: 4,
                        width: double.infinity,
                        color: const Color(0xFFEEEEEE),
                      ),
                      FractionallySizedBox(
                        widthFactor: doc['progress'],
                        child: Container(
                          height: 4,
                          color: const Color(0xFFCC0000),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // PDF Upload/Preview Section
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE8E8E8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "DOCUMENT PREVIEW",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        // Upload/Replace PDF button
                        GestureDetector(
                          onTap: _pickPdf,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              border: Border.all(
                                color: const Color(0xFFE8E8E8),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.upload_file_outlined,
                                  size: 13,
                                  color: Color(0xFFCC0000),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _pdfFile == null ? "UPLOAD PDF" : "REPLACE",
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1,
                                    color: Color(0xFFCC0000),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // PDF notice
                  if (_pdfFile == null)
                    const Padding(
                      padding: EdgeInsets.only(left: 16, bottom: 8),
                      child: Text(
                        "Only PDF files are supported.",
                        style: TextStyle(fontSize: 10, color: Colors.black38),
                      ),
                    ),

                  // PDF viewer or placeholder
                  if (_pdfFile == null)
                    SizedBox(
                      height: 280,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.picture_as_pdf_outlined,
                            size: 48,
                            color: Colors.black12,
                          ),
                          SizedBox(height: 12),
                          Text(
                            "NO PDF UPLOADED",
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black26,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "Tap UPLOAD PDF to select a file",
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black26,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    // PDF + draggable signature overlay
                    Column(
                      children: [
                        // Page indicator for multi-page PDFs
                        if (_pdfLoaded && _totalPages > 1)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "PAGE ${_currentPage + 1} OF $_totalPages",
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.black38,
                                    letterSpacing: 1,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Row(
                                  children: [
                                    GestureDetector(
                                      onTap: _currentPage > 0
                                          ? () => _pdfController?.setPage(
                                              _currentPage - 1,
                                            )
                                          : null,
                                      child: Icon(
                                        Icons.chevron_left,
                                        size: 20,
                                        color: _currentPage > 0
                                            ? const Color(0xFFCC0000)
                                            : Colors.black12,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: _currentPage < _totalPages - 1
                                          ? () => _pdfController?.setPage(
                                              _currentPage + 1,
                                            )
                                          : null,
                                      child: Icon(
                                        Icons.chevron_right,
                                        size: 20,
                                        color: _currentPage < _totalPages - 1
                                            ? const Color(0xFFCC0000)
                                            : Colors.black12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        SizedBox(
                          key: _pdfContainerKey,
                          height: 500,
                          child: Stack(
                            children: [
                              // PDF View — scrollable multi-page
                              PDFView(
                                filePath: _pdfFile!.path,
                                enableSwipe: true, // 👈 swipe between pages
                                swipeHorizontal: false, // 👈 vertical scroll
                                autoSpacing: true, // 👈 spacing between pages
                                pageFling: true, // 👈 smooth fling
                                pageSnap: true,
                                fitPolicy: FitPolicy.BOTH,
                                onRender: (pages) => setState(() {
                                  _pdfLoaded = true;
                                  _totalPages = pages ?? 1;
                                }),
                                onViewCreated: (controller) =>
                                    _pdfController = controller,
                                onPageChanged: (page, total) => setState(() {
                                  _currentPage = page ?? 0;
                                  _totalPages = total ?? 1;
                                }),
                                onError: (e) => debugPrint('PDF error: $e'),
                              ),

                              // Loading indicator
                              if (!_pdfLoaded)
                                const Center(
                                  child: CircularProgressIndicator(
                                    color: Color(0xFFCC0000),
                                  ),
                                ),

                              // Draggable Signature Overlay
                              if (_showSignatureOverlay)
                                Positioned(
                                  left: _signaturePosition.dx,
                                  top: _signaturePosition.dy,
                                  child: GestureDetector(
                                    onPanUpdate: (details) {
                                      setState(() {
                                        _signaturePosition += details.delta;
                                        final maxX =
                                            (MediaQuery.of(context).size.width -
                                                60) -
                                            140;
                                        final maxY = 500.0 - 80;
                                        _signaturePosition = Offset(
                                          _signaturePosition.dx.clamp(
                                            0.0,
                                            maxX,
                                          ),
                                          _signaturePosition.dy.clamp(
                                            0.0,
                                            maxY,
                                          ),
                                        );
                                      });
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: _signed
                                              ? Colors.transparent
                                              : const Color(
                                                  0xFFCC0000,
                                                ).withOpacity(0.5),
                                          width: 1,
                                        ),
                                        color: Colors.transparent,
                                      ),
                                      padding: const EdgeInsets.all(6),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (!_signed)
                                            const Padding(
                                              padding: EdgeInsets.only(
                                                bottom: 4,
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.open_with,
                                                    size: 10,
                                                    color: Colors.black38,
                                                  ),
                                                  SizedBox(width: 3),
                                                  Text(
                                                    "DRAG TO POSITION",
                                                    style: TextStyle(
                                                      fontSize: 8,
                                                      color: Colors.black38,
                                                      letterSpacing: 0.8,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          _buildSignatureWidget(),
                                          const SizedBox(height: 4),
                                          Text(
                                            _signedTimestamp,
                                            style: const TextStyle(
                                              fontSize: 8,
                                              color: Colors.black54,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 12),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Sign / Confirm Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSigning
                    ? null
                    : _signed
                    ? null
                    : _showSignatureOverlay
                    ? _confirmSign // 👈 confirm placement
                    : _onSignDocument, // 👈 show signature on PDF
                style: ElevatedButton.styleFrom(
                  backgroundColor: _signed
                      ? Colors.green
                      : _showSignatureOverlay
                      ? const Color(0xFF1565C0) // blue = confirm
                      : const Color(0xFFCC0000), // red = sign
                  disabledBackgroundColor: _signed
                      ? Colors.green
                      : const Color(0xFFCC0000).withOpacity(0.6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  elevation: 0,
                ),
                child: _isSigning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _signed
                                ? Icons.check_circle_outline
                                : _showSignatureOverlay
                                ? Icons.check
                                : Icons.draw_outlined,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _signed
                                ? "DOCUMENT SIGNED"
                                : _showSignatureOverlay
                                ? "CONFIRM PLACEMENT"
                                : "SIGN DOCUMENT",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 12),

            // Cancel
            Center(
              child: TextButton(
                onPressed: () {
                  if (_showSignatureOverlay && !_signed) {
                    setState(() => _showSignatureOverlay = false);
                  } else {
                    Navigator.pop(context);
                  }
                },
                child: Text(
                  _showSignatureOverlay && !_signed
                      ? "CANCEL PLACEMENT"
                      : "CANCEL AND GO BACK",
                  style: const TextStyle(
                    color: Colors.black45,
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Signing Notice
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  left: BorderSide(color: Color(0xFFCC0000), width: 3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "SIGNING NOTICE",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    "By signing this document, you confirm that you have reviewed and approved the contents. This action is logged and cannot be undone.",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: Colors.black38),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                color: Colors.black38,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF1A1A1A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
