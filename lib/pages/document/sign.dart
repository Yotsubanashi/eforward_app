import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:eforward_app/pages/dashboard/dashboard.dart';
import 'package:eforward_app/pages/document/view_sign.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_api.dart'; // 👈 import API

// ─── Signature Painter ───────────────────────────────────────────────────────

class SignaturePainter extends CustomPainter {
  final List<List<Offset?>> strokes;
  final Color penColor;

  SignaturePainter(this.strokes, {this.penColor = const Color(0xFF1A1A1A)});

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
  bool shouldRepaint(SignaturePainter oldDelegate) => true;
}

// ─── Sign Screen ─────────────────────────────────────────────────────────────

class SignScreen extends StatefulWidget {
  const SignScreen({super.key});

  @override
  State<SignScreen> createState() => _SignScreenState();
}

class _SignScreenState extends State<SignScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AuthApi _authApi = AuthApi(); // 👈 API instance

  // Draw tab
  final List<List<Offset?>> _strokes = [];
  List<Offset?> _currentStroke = [];
  final GlobalKey _canvasKey = GlobalKey();
  Color _penColor = const Color(0xFF1A1A1A);

  // Upload tab
  File? _uploadedImage;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _authApi.dispose(); // 👈 dispose API
    _tabController.dispose();
    super.dispose();
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

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _uploadedImage = File(picked.path));
  }

  // 👇 Upload signature image to API
  Future<void> _uploadSignatureToApi(
    SharedPreferences prefs,
    int currentTab,
  ) async {
    final token = prefs.getString('access_token') ?? '';

    if (token.isEmpty) {
      debugPrint('No token found, skipping signature upload.');
      return;
    }

    List<int>? imageBytes;
    String fileName = 'signature.png';

    if (currentTab == 0) {
      // Draw — capture canvas as PNG bytes
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
            imageBytes = byteData.buffer.asUint8List();
          }
        }
      } catch (e) {
        debugPrint('Canvas capture error: $e');
      }
      fileName = 'signature_draw.png';
    } else if (currentTab == 1 && _uploadedImage != null) {
      // Upload — read file bytes
      imageBytes = await _uploadedImage!.readAsBytes();
      fileName = 'signature_upload.png';
    }

    if (imageBytes == null) {
      debugPrint('No image bytes to upload.');
      return;
    }

    final result = await _authApi.uploadSignature(
      token: token,
      imageBytes: imageBytes,
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

  Future<void> _saveSignature() async {
    final currentTab = _tabController.index;

    // Validate before saving
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

    final prefs = await SharedPreferences.getInstance();

    if (currentTab == 0) {
      // Draw — capture canvas as base64 PNG
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
            final base64Str = base64Encode(byteData.buffer.asUint8List());
            await prefs.setString('signature_draw_data', base64Str);
          }
        }
      } catch (e) {
        debugPrint('Draw capture error: $e');
      }
      await prefs.setString('signature_type', 'draw');
    } else {
      // Upload
      await prefs.setString('signature_type', 'upload');
      if (_uploadedImage != null) {
        await prefs.setString('signature_image_path', _uploadedImage!.path);
      }
    }

    // Save timestamp in Philippine time (PHT/GMT+8)
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
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
    final timestamp =
        '${months[now.month - 1]} ${now.day}, ${now.year} · ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} PHT';
    await prefs.setString('signature_timestamp', timestamp);
    await prefs.setBool('has_signature', true);

    // 👇 Upload to API after saving locally
    await _uploadSignatureToApi(prefs, currentTab);

    // ── Clear image cache to ensure fresh data is fetched ──
    await Future.delayed(const Duration(milliseconds: 600));
    imageCache.clear();
    imageCache.clearLiveImages();

    setState(() => _isSaving = false);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ViewSignPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
          onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            final hasSignature = prefs.getBool('has_signature') ?? false;
            if (mounted) {
              if (hasSignature) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const ViewSignPage()),
                );
              } else {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const DashboardPage()),
                );
              }
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
              style: TextStyle(
                fontSize: 12,
                color: Colors.black45,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),

            // Tab Bar
            Container(
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
                  Tab(text: "UPLOAD"),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Tab Content
            SizedBox(
              height: 320,
              child: TabBarView(
                controller: _tabController,
                children: [_buildDrawTab(), _buildUploadTab()],
              ),
            ),
            const SizedBox(height: 24),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveSignature,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFCC0000),
                  disabledBackgroundColor: const Color(
                    0xFFCC0000,
                  ).withOpacity(0.6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  elevation: 0,
                ),
                child: _isSaving
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
                        children: const [
                          Icon(
                            Icons.draw_outlined,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            "SAVE SIGNATURE",
                            style: TextStyle(
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
                            fontSize: 12,
                            color: Colors.black54,
                            height: 1.6,
                          ),
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
    );
  }

  // ─── DRAW TAB ───────────────────────────────────────────────────────────────
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
                GestureDetector(
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: RepaintBoundary(
                    key: _canvasKey,
                    child: CustomPaint(
                      painter: SignaturePainter(_strokes, penColor: _penColor),
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
        const SizedBox(height: 12),
        Row(
          children: [
            GestureDetector(
              onTap: _undoStroke,
              child: Row(
                children: const [
                  Icon(Icons.undo, size: 16, color: Colors.black45),
                  SizedBox(width: 4),
                  Text(
                    "UNDO",
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
            const SizedBox(width: 20),
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
            const SizedBox(width: 16),
            _buildColorDot(const Color(0xFF1A1A1A)),
            const SizedBox(width: 8),
            _buildColorDot(const Color(0xFFCC0000)),
            const SizedBox(width: 8),
            _buildColorDot(const Color(0xFF1565C0)),
          ],
        ),
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

  // ─── UPLOAD TAB ───────────────────────────────────────────────────────────────
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
        const SizedBox(height: 12),
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
      ],
    );
  }
}
