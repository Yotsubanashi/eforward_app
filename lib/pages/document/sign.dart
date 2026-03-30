import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';

// ─── Signature Painter ───────────────────────────────────────────────────────

class SignaturePainter extends CustomPainter {
  final List<List<Offset?>> strokes;

  SignaturePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A1A1A)
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

  // Draw tab
  final List<List<Offset?>> _strokes = [];
  List<Offset?> _currentStroke = [];
  final GlobalKey _canvasKey = GlobalKey();
  Color _penColor = const Color(0xFF1A1A1A);

  // Type tab
  final TextEditingController _typeController = TextEditingController();
  String _selectedFont = 'Cursive';
  final List<String> _fonts = ['Cursive', 'Serif', 'Script'];

  // Capture tab
  File? _uploadedImage;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _typeController.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _currentStroke = [details.localPosition];
      _strokes.add(_currentStroke);
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _currentStroke.add(details.localPosition);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _currentStroke.add(null);
    });
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

  Future<void> _saveSignature() async {
    setState(() => _isSaving = true);
    await Future.delayed(const Duration(milliseconds: 1200));
    setState(() => _isSaving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Signature saved successfully!"),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
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
          onPressed: () => Navigator.pop(context),
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
            // Title
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
                  Tab(text: "TYPE"),
                  Tab(text: "CAPTURE"),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Tab Content
            SizedBox(
              height: 320,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDrawTab(),
                  _buildTypeTab(),
                  _buildCaptureTab(),
                ],
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
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Color(0xFFCC0000),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
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
        // Canvas
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE8E8E8)),
            ),
            child: Stack(
              children: [
                // Drawing area
                GestureDetector(
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: RepaintBoundary(
                    key: _canvasKey,
                    child: CustomPaint(
                      painter: SignaturePainter(_strokes),
                      size: Size.infinite,
                    ),
                  ),
                ),

                // Sign above line hint
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

        // Controls
        Row(
          children: [
            // Undo
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

            // Clear
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

            // Color dots
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

  // ─── TYPE TAB ───────────────────────────────────────────────────────────────
  Widget _buildTypeTab() {
    return Column(
      children: [
        // Preview
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
                  fontFamily: _selectedFont == 'Cursive'
                      ? 'cursive'
                      : _selectedFont == 'Serif'
                      ? 'serif'
                      : null,
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

        // Text input
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

        // Font selector
        Row(
          children: _fonts.map((font) {
            final selected = _selectedFont == font;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _selectedFont = font),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
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

  // ─── CAPTURE TAB ────────────────────────────────────────────────────────────
  Widget _buildCaptureTab() {
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

        // Re-upload button
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
