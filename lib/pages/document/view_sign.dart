import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:eforward_app/pages/dashboard/dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eforward_app/components/bottom_navigator.dart';
import '../../services/auth_api.dart';

// ─── Signature Painter ───────────────────────────────────────────────────────

class _SignaturePainter extends CustomPainter {
  final List<List<Offset?>> strokes;
  final Color penColor;

  _SignaturePainter(this.strokes, {this.penColor = const Color(0xFF1A1A1A)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = penColor
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      final path = Path();
      bool started = false;
      for (final point in stroke) {
        if (point == null) {
          started = false;
        } else if (!started) {
          path.moveTo(point.dx, point.dy);
          started = true;
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter oldDelegate) => true;
}

// ─── View Sign Page ───────────────────────────────────────────────────────────

class ViewSignPage extends StatefulWidget {
  const ViewSignPage({super.key});

  @override
  State<ViewSignPage> createState() => _ViewSignPageState();
}

class _ViewSignPageState extends State<ViewSignPage>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 1;
  bool _isEditMode = false;

  late TabController _tabController;
  final AuthApi _authApi = AuthApi();

  // Loaded signature data
  String _signatureType = '';
  String _signatureText = '';
  String _signatureFont = 'Cursive';
  String _signatureImagePath = '';
  String? _drawBase64;
  String? _apiSignatureUrl;      // URL from API JSON response
  List<int>? _apiSignatureBytes; // raw bytes from API blob response

  // Draw tab (edit mode)
  final List<List<Offset?>> _strokes = [];
  List<Offset?> _currentStroke = [];
  final GlobalKey _canvasKey = GlobalKey();
  Color _penColor = const Color(0xFF1A1A1A);

  // Type tab (edit mode)
  final TextEditingController _typeController = TextEditingController();
  String _selectedFont = 'Cursive';
  final List<String> _fonts = ['Cursive', 'Serif', 'Script'];

  // Capture tab (edit mode)
  File? _uploadedImage;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSignature();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _typeController.dispose();
    _authApi.dispose();
    super.dispose();
  }

  Future<void> _loadSignature() async {
    final prefs = await SharedPreferences.getInstance();

    // Load local data first
    setState(() {
      _signatureType = prefs.getString('signature_type') ?? '';
      _signatureText = prefs.getString('signature_text') ?? '';
      _signatureFont = prefs.getString('signature_font') ?? 'Cursive';
      _signatureImagePath = prefs.getString('signature_image_path') ?? '';
      _drawBase64 = prefs.getString('signature_draw_data');
      

      if (_signatureType == 'type') {
        _typeController.text = _signatureText;
        _selectedFont = _signatureFont;
      }
    });

    // Then fetch from API
    await _fetchSignatureFromApi(prefs);
  }

  Future<void> _fetchSignatureFromApi(SharedPreferences prefs) async {
    final token = prefs.getString('access_token') ?? '';
    debugPrint('=== TOKEN IN VIEW SIGN: $token ===');

    if (token.isEmpty) {
      debugPrint('No token found, skipping signature API fetch.');
      return;
    }

  

    final result = await _authApi.getSignature(token: token);

    if (!mounted) return;

    

    if (result.isSuccess) {
      // Case 1: Raw image bytes
      if (result.imageBytes != null && result.imageBytes!.isNotEmpty) {
        debugPrint('Signature loaded as bytes');
        setState(() => _apiSignatureBytes = result.imageBytes);
      }

      // Case 2: URL
      if (result.imageUrl != null && result.imageUrl!.isNotEmpty) {
        debugPrint('Signature URL: ${result.imageUrl}');
        setState(() => _apiSignatureUrl = result.imageUrl);
      }

      // Case 3: base64 inside data.base64 (YOUR API FORMAT)
      final dynamic responseData = result.data;
      if (responseData is Map) {
        final dynamic inner = responseData['data'];
        if (inner is Map) {
          final base64Str = inner['base64'] as String?;
          if (base64Str != null && base64Str.isNotEmpty) {
            debugPrint('Found base64 in data.base64');
            final pureBase64 = base64Str.contains(',')
                ? base64Str.split(',').last
                : base64Str;
            try {
              final bytes = base64Decode(pureBase64);
              setState(() => _apiSignatureBytes = bytes);
              debugPrint('Decoded signature: ${bytes.length} bytes');
            } catch (e) {
              debugPrint('Base64 decode error: $e');
            }
          }
        }
      }

      // Extract date
     
    } else {
      debugPrint('Signature API failed [${result.statusCode}]: ${result.message}');
    }
  }

  void _enterEditMode() {
    setState(() {
      _isEditMode = true;
      _strokes.clear();
    });
  }

  Future<void> _saveSignature() async {
    final currentTab = _tabController.index;

    if (currentTab == 0 && _strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please draw your signature first."),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
      return;
    }
    if (currentTab == 1 && _typeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please type your signature first."),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
      return;
    }
    if (currentTab == 2 && _uploadedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please upload a signature image first."),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final prefs = await SharedPreferences.getInstance();

    if (currentTab == 0) {
      try {
        final boundary = _canvasKey.currentContext
            ?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 3.0);
          final byteData =
              await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final base64Str = base64Encode(byteData.buffer.asUint8List());
            await prefs.setString('signature_draw_data', base64Str);
            setState(() => _drawBase64 = base64Str);
          }
        }
      } catch (e) {
        debugPrint('Draw capture error: $e');
      }
      await prefs.setString('signature_type', 'draw');
      setState(() => _signatureType = 'draw');
    } else if (currentTab == 1) {
      await prefs.setString('signature_type', 'type');
      await prefs.setString('signature_text', _typeController.text.trim());
      await prefs.setString('signature_font', _selectedFont);
      setState(() {
        _signatureType = 'type';
        _signatureText = _typeController.text.trim();
        _signatureFont = _selectedFont;
      });
    } else {
      await prefs.setString('signature_type', 'capture');
      if (_uploadedImage != null) {
        await prefs.setString('signature_image_path', _uploadedImage!.path);
        setState(() {
          _signatureType = 'capture';
          _signatureImagePath = _uploadedImage!.path;
        });
      }
    }

  
   

    setState(() {
      
      _isSaving = false;
      _isEditMode = false;
      _apiSignatureUrl = null;
      _apiSignatureBytes = null; // 👈 reset so it re-fetches after save
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Signature saved successfully!"),
          backgroundColor: Colors.green,
        ),
      );

      // Re-fetch from API to get updated image URL
      await _fetchSignatureFromApi(prefs);
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _uploadedImage = File(picked.path));
  }

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _currentStroke = [details.localPosition];
      _strokes.add(_currentStroke);
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() => _currentStroke.add(details.localPosition));
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() => _currentStroke.add(null));
  }

  void _undoStroke() {
    if (_strokes.isNotEmpty) setState(() => _strokes.removeLast());
  }

  void _clearCanvas() {
    setState(() => _strokes.clear());
  }

  // ─── Signature Preview ────────────────────────────────────────────────────

  Widget _buildSavedSignaturePreview() {
    // Priority 1: API blob bytes
    if (_apiSignatureBytes != null && _apiSignatureBytes!.isNotEmpty) {
      debugPrint('Displaying API signature bytes');
      return Center(
        child: Image.memory(
          Uint8List.fromList(_apiSignatureBytes!),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Bytes image error: $error');
            return _buildLocalSignaturePreview();
          },
        ),
      );
    }

    // Priority 2: API URL
    if (_apiSignatureUrl != null && _apiSignatureUrl!.isNotEmpty) {
      debugPrint('Displaying API signature URL: $_apiSignatureUrl');
      return Center(
        child: Image.network(
          _apiSignatureUrl!,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFCC0000)),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            debugPrint('URL image error: $error');
            return _buildLocalSignaturePreview();
          },
        ),
      );
    }

    // Priority 3: Fallback to local
    return _buildLocalSignaturePreview();
  }

  Widget _buildLocalSignaturePreview() {
    if (_signatureType == 'draw' && _drawBase64 != null) {
      return Center(
        child: Image.memory(base64Decode(_drawBase64!), fit: BoxFit.contain),
      );
    } else if (_signatureType == 'type' && _signatureText.isNotEmpty) {
      return Center(
        child: Text(
          _signatureText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 32,
            fontStyle: FontStyle.italic,
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w300,
          ),
        ),
      );
    } else if (_signatureType == 'capture' && _signatureImagePath.isNotEmpty) {
      return Center(
        child: Image.file(File(_signatureImagePath), fit: BoxFit.contain),
      );
    }
    return const Center(
      child: Text(
        "No signature found",
        style: TextStyle(fontSize: 12, color: Colors.black26),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F5F7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A1A1A), size: 20),
          onPressed: () {
            if (_isEditMode) {
              setState(() {
                _isEditMode = false;
                _strokes.clear();
              });
            } else {
               Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const DashboardPage()),
            );
            }
          },
        ),
        title: const Text(
          "SIGNATURE",
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "DIGITAL\nSIGNATURE",
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                height: 1.1,
                color: Color(0xFF1A1A1A),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              width: 40,
              height: 3,
              color: const Color(0xFFCC0000),
            ),
            const Text(
              "Institutional-grade verification for secure documentation. Create, type, or upload your legal identifier below.",
              style: TextStyle(fontSize: 12, color: Colors.black45, height: 1.6),
            ),

            const SizedBox(height: 24),

            // Tab Bar
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE8E8E8))),
              ),
              child: IgnorePointer(
                ignoring: !_isEditMode,
                child: TabBar(
                  controller: _tabController,
                  labelColor:
                      _isEditMode ? const Color(0xFFCC0000) : Colors.black38,
                  unselectedLabelColor: Colors.black26,
                  indicatorColor: _isEditMode
                      ? const Color(0xFFCC0000)
                      : Colors.transparent,
                  indicatorWeight: 2,
                  labelStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                  ),
                  tabs: const [
                    Tab(text: "DRAW"),
                    Tab(text: "TYPE"),
                    Tab(text: "CAPTURE"),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Tab Content
            SizedBox(
              height: 320,
              child: _isEditMode
                  ? TabBarView(
                      controller: _tabController,
                      children: [
                        _buildDrawTab(editMode: true),
                        _buildTypeTab(editMode: true),
                        _buildCaptureTab(editMode: true),
                      ],
                    )
                  : _buildDrawTab(editMode: false),
            ),

            const SizedBox(height: 12),

            const SizedBox(height: 24),

            // Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving
                    ? null
                    : _isEditMode
                        ? _saveSignature
                        : _enterEditMode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFCC0000),
                  disabledBackgroundColor:
                      const Color(0xFFCC0000).withOpacity(0.6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isEditMode ? Icons.draw_outlined : Icons.edit,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isEditMode ? "SAVE SIGNATURE" : "EDIT SIGNATURE",
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

            const SizedBox(height: 24),

            // Legal Validity Notice
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  left: BorderSide(color: Color(0xFFCC0000), width: 3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.info_outline, color: Color(0xFFCC0000), size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "LEGAL VALIDITY",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          "This signature will be cryptographically bound to your E-FORWARD identity. Ensure the signature is clear and legible for high-security verification protocols.",
                          style: TextStyle(
                              fontSize: 12, color: Colors.black54, height: 1.6),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigator(
        selectedIndex: _selectedIndex,
        onTap: (_) {},
      ),
    );
  }

  // ─── DRAW TAB ──────────────────────────────────────────────────────────────
  Widget _buildDrawTab({required bool editMode}) {
    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE8E8E8)),
            ),
            child: editMode
                ? Stack(
                    children: [
                      GestureDetector(
                        onPanStart: _onPanStart,
                        onPanUpdate: _onPanUpdate,
                        onPanEnd: _onPanEnd,
                        child: RepaintBoundary(
                          key: _canvasKey,
                          child: CustomPaint(
                            painter: _SignaturePainter(_strokes,
                                penColor: _penColor),
                            size: Size.infinite,
                          ),
                        ),
                      ),
                      if (_strokes.isEmpty)
                        const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              SizedBox(height: 120),
                              Padding(
                                padding:
                                    EdgeInsets.symmetric(horizontal: 24),
                                child: Divider(
                                    color: Color(0xFFCCCCCC), thickness: 1),
                              ),
                              SizedBox(height: 6),
                              Text(
                                "SIGN ABOVE THIS LINE",
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.black26,
                                  letterSpacing: 1.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 16),
                            ],
                          ),
                        ),
                    ],
                  )
                : _buildSavedSignaturePreview(), // 👈 uses API or local
          ),
        ),
        const SizedBox(height: 12),
        if (editMode)
          Row(
            children: [
              GestureDetector(
                onTap: _undoStroke,
                child: Row(
                  children: const [
                    Icon(Icons.undo, size: 16, color: Colors.black45),
                    SizedBox(width: 4),
                    Text("UNDO",
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.black45,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              GestureDetector(
                onTap: _clearCanvas,
                child: Row(
                  children: const [
                    Icon(Icons.close, size: 16, color: Colors.black45),
                    SizedBox(width: 4),
                    Text("CLEAR",
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.black45,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _buildColorDot(const Color(0xFF1A1A1A)),
              const SizedBox(width: 8),
              _buildColorDot(const Color(0xFFCC0000)),
              const SizedBox(width: 8),
              _buildColorDot(const Color(0xFF1565C0)),
            ],
          )
        else
          const SizedBox(height: 26),
      ],
    );
  }

  Widget _buildColorDot(Color color) {
    final selected = _penColor == color;
    return GestureDetector(
      onTap: () => setState(() => _penColor = color),
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? Colors.white : Colors.transparent,
            width: 2,
          ),
          boxShadow: selected
              ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 4)]
              : [],
        ),
      ),
    );
  }

  // ─── TYPE TAB ──────────────────────────────────────────────────────────────
  Widget _buildTypeTab({required bool editMode}) {
    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE8E8E8)),
            ),
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                _typeController.text.isEmpty
                    ? "Your signature will appear here"
                    : _typeController.text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: _typeController.text.isEmpty ? 13 : 28,
                  fontStyle: FontStyle.italic,
                  color: _typeController.text.isEmpty
                      ? Colors.black26
                      : const Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _typeController,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A1A)),
          decoration: const InputDecoration(
            hintText: "Type your full name...",
            hintStyle: TextStyle(color: Colors.black26, fontSize: 12),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFE8E8E8)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFCC0000)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: _fonts.map((font) {
            final selected = _selectedFont == font;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _selectedFont = font),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFCC0000)
                        : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? const Color(0xFFCC0000)
                          : Colors.black26,
                    ),
                  ),
                  child: Text(
                    font.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: selected ? Colors.white : Colors.black45,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ─── CAPTURE TAB ───────────────────────────────────────────────────────────
  Widget _buildCaptureTab({required bool editMode}) {
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: editMode ? _pickImage : null,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE8E8E8)),
              ),
              child: _uploadedImage != null
                  ? Image.file(_uploadedImage!, fit: BoxFit.contain)
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.upload_file_outlined,
                            size: 40, color: Colors.black12),
                        SizedBox(height: 12),
                        Text(
                          "TAP TO UPLOAD SIGNATURE",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.black26,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "JPG, PNG supported",
                          style:
                              TextStyle(fontSize: 11, color: Colors.black26),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (editMode && _uploadedImage != null)
          GestureDetector(
            onTap: _pickImage,
            child: Row(
              children: const [
                Icon(Icons.refresh, size: 16, color: Colors.black45),
                SizedBox(width: 4),
                Text("REPLACE IMAGE",
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.black45,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1)),
              ],
            ),
          ),
      ],
    );
  }
}