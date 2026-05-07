import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eforward_app/components/bottom_navigator.dart';
import '../../services/auth_api.dart';

// ─── Signature Painter ────────────────────────────────────────────────────────

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
  final int _selectedIndex = 1;
  bool _isEditMode = false;

  late TabController _tabController;
  final AuthApi _authApi = AuthApi();

  // Loaded signature data
  String _signatureType = '';
  String _signatureImagePath = '';
  String? _drawBase64;
  bool _isLoadingSignature = false;
  List<int>? _apiSignatureBytes;

  // Metadata
  String _signerName = '';
  String _signerEmployeeId = '';
  DateTime? _signedAt;
  bool _showMetadata = false;

  // Draw tab (edit mode)
  final List<List<Offset?>> _strokes = [];
  List<Offset?> _currentStroke = [];
  final GlobalKey _canvasKey = GlobalKey();

  // Upload tab (edit mode)
  File? _uploadedImage;

  bool _isSaving = false;
  Uint8List? _watermarkBytes;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSignature();
    _loadWatermark();
    _loadUserInfo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _authApi.dispose();
    super.dispose();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataStr = prefs.getString('user_data');
    if (userDataStr != null) {
      try {
        final full = jsonDecode(userDataStr) as Map<String, dynamic>;
        Map<String, dynamic>? userData;
        if (full['user'] is Map)
          userData = full['user'] as Map<String, dynamic>;
        else if (full['data'] is Map)
          userData = full['data'] as Map<String, dynamic>;
        else
          userData = full;

        final first =
            userData['fname'] ??
            userData['first_name'] ??
            userData['firstName'] ??
            '';
        final last =
            userData['lname'] ??
            userData['last_name'] ??
            userData['lastName'] ??
            '';
        final empId =
            userData['employee_id'] ??
            userData['employeeId'] ??
            userData['emp_id'] ??
            '';
        if (mounted) {
          setState(() {
            _signerName = [first, last]
                .map((p) => p.toString().trim())
                .where((p) => p.isNotEmpty)
                .join(' ')
                .trim();
            _signerEmployeeId = empId.toString().trim();
            _signedAt = DateTime.now();
          });
        }
      } catch (e) {
        debugPrint('Error loading user info: $e');
      }
    }
  }

  Future<void> _loadWatermark() async {
    try {
      final byteData = await rootBundle.load(
        'assets/images/eforward_watermark.png',
      );
      if (mounted) {
        setState(() {
          _watermarkBytes = byteData.buffer.asUint8List();
        });
      }
    } catch (e) {
      debugPrint('Watermark load error: $e');
    }
  }

  Future<void> _loadSignature() async {
    imageCache.clear();
    imageCache.clearLiveImages();

    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _signatureType = prefs.getString('signature_type') ?? '';
      _signatureImagePath = prefs.getString('signature_image_path') ?? '';
      _drawBase64 = prefs.getString('signature_draw_data');
    });
    await _fetchSignatureFromApi(prefs);
  }

  Future<void> _fetchSignatureFromApi(SharedPreferences prefs) async {
    final token = prefs.getString('access_token') ?? '';
    if (token.isEmpty) return;

    setState(() => _isLoadingSignature = true);

    final result = await _authApi.getSignature(token: token);

    if (!mounted) return;

    if (result.isSuccess) {
      if (result.imageBytes != null && result.imageBytes!.isNotEmpty) {
        setState(() {
          _apiSignatureBytes = result.imageBytes;
          _isLoadingSignature = false;
        });
      } else {
        setState(() => _isLoadingSignature = false);
      }

      if (result.rawDate != null && result.rawDate!.isNotEmpty) {
        try {
          final parsed = DateTime.parse(result.rawDate!).toLocal();
          final months = [
            'JAN',
            'FEB',
            'MAR',
            'APR',
            'MAY',
            'JUN',
            'JUL',
            'AUG',
            'SEP',
            'OCT',
            'NOV',
            'DEC',
          ];
          final formatted =
              '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
          await prefs.setString('signature_timestamp', formatted);
        } catch (e) {
          debugPrint('Date parse error: $e');
        }
      }
    } else {
      setState(() => _isLoadingSignature = false);
      debugPrint(
        'Signature API failed [${result.statusCode}]: ${result.message}',
      );
    }
  }

  void _enterEditMode() {
    setState(() => _isEditMode = true);
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
    if (currentTab == 1 && _uploadedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please upload a signature image first."),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    List<int>? capturedBytes;
    String fileName = 'signature.png';

    if (currentTab == 0) {
      try {
        final boundary =
            _canvasKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
        if (boundary != null) {
          final image = await boundary.toImage(pixelRatio: 3.0);
          final byteData = await image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (byteData != null) {
            capturedBytes = byteData.buffer.asUint8List();
            fileName = 'signature_draw.png';
          }
        }
      } catch (e) {
        debugPrint('Canvas capture error: $e');
      }
    } else if (currentTab == 1 && _uploadedImage != null) {
      capturedBytes = await _uploadedImage!.readAsBytes();
      fileName = 'signature_upload.png';
    }

    if (capturedBytes == null || capturedBytes.isEmpty) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to capture signature. Please try again."),
            backgroundColor: Color(0xFFCC0000),
          ),
        );
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    if (currentTab == 0) {
      final base64Str = base64Encode(capturedBytes);
      await prefs.setString('signature_draw_data', base64Str);
      await prefs.setString('signature_type', 'draw');
      setState(() {
        _drawBase64 = base64Str;
        _signatureType = 'draw';
      });
    } else {
      await prefs.setString('signature_type', 'upload');
      if (_uploadedImage != null) {
        await prefs.setString('signature_image_path', _uploadedImage!.path);
        setState(() {
          _signatureType = 'upload';
          _signatureImagePath = _uploadedImage!.path;
        });
      }
    }

    final now = DateTime.now();
    final months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    final timestamp = '${months[now.month - 1]} ${now.day}, ${now.year}';
    await prefs.setString('signature_timestamp', timestamp);
    await prefs.setBool('has_signature', true);

    final token = prefs.getString('access_token') ?? '';
    if (token.isNotEmpty) {
      final result = await _authApi.uploadSignature(
        token: token,
        imageBytes: capturedBytes,
        fileName: fileName,
      );

      if (result.isSuccess) {
        debugPrint('Signature uploaded successfully: ${result.data}');
      } else {
        debugPrint(
          'Signature upload failed [${result.statusCode}]: ${result.message}',
        );
      }
    }

    await Future.delayed(const Duration(milliseconds: 600));

    setState(() {
      _apiSignatureBytes = null;
    });

    imageCache.clear();
    imageCache.clearLiveImages();

    await _fetchSignatureFromApi(prefs);

    if (mounted) {
      setState(() {
        _isSaving = false;
        _isEditMode = false;
        _strokes.clear();
        _uploadedImage = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Signature updated successfully!"),
          backgroundColor: Colors.green,
        ),
      );
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

  void _clearCanvas() {
    setState(() => _strokes.clear());
  }

  // ─── Signature Preview ─────────────────────────────────────────────────────

  Widget _buildSavedSignaturePreview() {
    if (_isLoadingSignature) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFCC0000)),
      );
    }

    return _buildSignatureWithMetadata();
  }

  Widget _buildSignatureWithMetadata() {
    // Default dimensions for the preview
    final double previewWidth = 300.0;
    final double previewHeight = 80.0;

    // Calculate responsive sizes based on preview height - IMPROVED SCALING
    final responsiveFontSize = (previewHeight * 0.14).clamp(4.0, 12.0);
    final responsiveLabelFontSize = (previewHeight * 0.12).clamp(3.5, 10.0);
    final responsivePadding = (previewHeight * 0.08).clamp(0.5, 2.0);
    final responsiveSpacing = (previewHeight * 0.06).clamp(2.0, 5.0);

    final now = (_signedAt ?? DateTime.now()).toUtc().add(
      const Duration(hours: 8),
    );
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    Widget signatureImage;
    if (_apiSignatureBytes != null && _apiSignatureBytes!.isNotEmpty) {
      signatureImage = Image.memory(
        Uint8List.fromList(_apiSignatureBytes!),
        fit: BoxFit.contain,
      );
    } else if (_signatureType == 'draw' && _drawBase64 != null) {
      signatureImage = Image.memory(
        base64Decode(_drawBase64!),
        fit: BoxFit.contain,
      );
    } else if (_signatureType == 'upload' && _signatureImagePath.isNotEmpty) {
      signatureImage = Image.file(
        File(_signatureImagePath),
        fit: BoxFit.contain,
      );
    } else {
      signatureImage = const Center(
        child: Text(
          "No signature",
          style: TextStyle(fontSize: 12, color: Colors.black26),
        ),
      );
    }

    return Container(
      width: previewWidth,
      height: previewHeight,
      color: Colors.transparent,
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Stack(
              alignment: Alignment.center,
              children: [
                signatureImage,
                if (_watermarkBytes != null)
                  Opacity(
                    opacity: 0.15,
                    child: Image.memory(_watermarkBytes!, fit: BoxFit.contain),
                  ),
              ],
            ),
          ),
          if (_showMetadata)
            // AFTER
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.only(right: 8.0), // ← ADD THIS
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFF1B5E20),
                    width: responsivePadding * 0.6,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  // ← FIXED PADDING
                  horizontal: 8.0,
                  vertical: 6.0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _metaRow(
                      'Digitally signed by:',
                      _signerName,
                      responsiveFontSize,
                      responsiveLabelFontSize,
                      responsiveSpacing,
                    ),
                    SizedBox(height: responsiveSpacing * 0.5),
                    _metaRow(
                      'Employee ID:',
                      _signerEmployeeId,
                      responsiveFontSize,
                      responsiveLabelFontSize,
                      responsiveSpacing,
                    ),
                    SizedBox(height: responsiveSpacing * 0.5),
                    _metaRow(
                      'Date:',
                      dateStr,
                      responsiveFontSize,
                      responsiveLabelFontSize,
                      responsiveSpacing,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _metaRow(
    String label,
    String value,
    double fontSize,
    double labelFontSize,
    double spacing,
  ) {
    return RichText(
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      text: TextSpan(
        style: TextStyle(
          fontSize: labelFontSize,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF1A1A1A),
          height: 1.1,
        ),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: value,
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.normal),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalSignatureWidget() {
    if (_signatureType == 'draw' && _drawBase64 != null) {
      return Center(
        child: Image.memory(base64Decode(_drawBase64!), fit: BoxFit.contain),
      );
    } else if (_signatureType == 'upload' && _signatureImagePath.isNotEmpty) {
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

  // ─── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "DIGITAL\nSIGNATURE",
            style: TextStyle(
              fontSize: 24, // Reduced from 30
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              height: 1.1,
              color: Color(0xFF1A1A1A),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 6, bottom: 8),
            width: 30, // Reduced from 40
            height: 3,
            color: const Color(0xFFCC0000),
          ),
          const Text(
            "View or update your legal identifier for secure documentation.",
            style: TextStyle(fontSize: 11, color: Colors.black45, height: 1.4),
          ),
          const SizedBox(height: 10), // Reduced from 16
        ],
      ),
    );
  }

  // ─── Body (preview or edit) ────────────────────────────────────────────────

  Widget _buildBody() {
    // VIEW MODE: show saved signature preview
    if (!_isEditMode) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFE8E8E8)),
                ),
                child: _buildSavedSignaturePreview(),
              ),
            ),
            const SizedBox(height: 10),
            // Button to show/hide metadata
            GestureDetector(
              onTap: () => setState(() => _showMetadata = !_showMetadata),
              child: Row(
                children: [
                  Icon(
                    _showMetadata ? Icons.visibility : Icons.visibility_off,
                    color: const Color(0xFFCC0000),
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _showMetadata ? "HIDE DETAILS" : "SHOW DIGITAL SIGNATURE",
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFCC0000),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Legal notice shown only in view mode - more compact
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  left: BorderSide(color: Color(0xFFCC0000), width: 3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.info_outline, color: Color(0xFFCC0000), size: 14),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "LEGAL VALIDITY",
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          "This signature is cryptographically bound to your identity.",
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.black54,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    }

    // EDIT MODE: tabs + canvas/upload, fills all available space
    return Column(
      children: [
        // TabBar — fixed height
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE8E8E8))),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFFCC0000),
              unselectedLabelColor: Colors.black38,
              indicatorColor: const Color(0xFFCC0000),
              indicatorWeight: 2,
              labelStyle: const TextStyle(
                fontSize: 10, // Reduced from 11
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
              tabs: const [
                Tab(text: "DRAW"),
                Tab(text: "UPLOAD"),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8), // Reduced from 12
        // TabBarView fills all remaining vertical space
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: TabBarView(
              controller: _tabController,
              // Disable swipe so horizontal draw strokes don't switch tabs
              physics: const NeverScrollableScrollPhysics(),
              children: [_buildDrawTab(), _buildUploadTab()],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Bottom action button ──────────────────────────────────────────────────

  Widget _buildBottomActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), // Reduced bottom padding
      child: SizedBox(
        width: double.infinity,
        height: 46, // Reduced from 50
        child: ElevatedButton(
          onPressed: _isSaving
              ? null
              : _isEditMode
              ? _saveSignature
              : _enterEditMode,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFCC0000),
            disabledBackgroundColor: const Color(0xFFCC0000).withOpacity(0.6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            elevation: 0,
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isEditMode ? Icons.save_outlined : Icons.edit,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isEditMode ? "SAVE SIGNATURE" : "REPLACE SIGNATURE",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F5F7),
        elevation: 0,
        automaticallyImplyLeading: false, // ← ADD THIS LINE
        leading: _isEditMode
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  color: Color(0xFF1A1A1A),
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    _isEditMode = false;
                    _strokes.clear();
                    _uploadedImage = null;
                  });
                },
              )
            : null,
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
      // ── Non-scrollable body: Column with fixed header, Expanded body, fixed footer
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          Expanded(child: _buildBody()),
          _buildBottomActions(),
        ],
      ),
      bottomNavigationBar: BottomNavigator(
        selectedIndex: _selectedIndex,
        onTap: (_) {},
      ),
    );
  }

  // ─── DRAW TAB ──────────────────────────────────────────────────────────────

  Widget _buildDrawTab() {
    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE8E8E8)),
            ),
            child: Stack(
              children: [
                // Watermark behind drawing area
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.08,
                    child: Center(
                      child: Image.asset(
                        'assets/images/eforward_watermark.png',
                        fit: BoxFit.contain,
                        width: 180,
                        height: 180,
                      ),
                    ),
                  ),
                ),
                // Drawing layer
                GestureDetector(
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: RepaintBoundary(
                    key: _canvasKey,
                    child: CustomPaint(
                      painter: _SignaturePainter(_strokes),
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
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          child: Divider(
                            color: Color(0xFFCCCCCC),
                            thickness: 1,
                          ),
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
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            GestureDetector(
              onTap: _clearCanvas,
              child: Row(
                children: const [
                  Icon(Icons.close, size: 16, color: Colors.black45),
                  SizedBox(width: 4),
                  Text(
                    "CLEAR",
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.black45,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  // ─── UPLOAD TAB ────────────────────────────────────────────────────────────

  Widget _buildUploadTab() {
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _pickImage,
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
                        Icon(
                          Icons.upload_file_outlined,
                          size: 40,
                          color: Colors.black12,
                        ),
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
                          style: TextStyle(fontSize: 11, color: Colors.black26),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_uploadedImage != null)
          GestureDetector(
            onTap: _pickImage,
            child: Row(
              children: const [
                Icon(Icons.refresh, size: 16, color: Colors.black45),
                SizedBox(width: 4),
                Text(
                  "REPLACE IMAGE",
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.black45,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}
