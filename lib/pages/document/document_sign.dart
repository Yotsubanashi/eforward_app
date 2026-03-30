import 'package:flutter/material.dart';

class DocumentSignScreen extends StatefulWidget {
  final Map<String, dynamic> document;
  const DocumentSignScreen({super.key, required this.document});

  @override
  State<DocumentSignScreen> createState() => _DocumentSignScreenState();
}

class _DocumentSignScreenState extends State<DocumentSignScreen> {
  bool _isSigning = false;
  bool _signed = false;

  Future<void> _signDocument() async {
    setState(() => _isSigning = true);
    await Future.delayed(const Duration(milliseconds: 1500));
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

                  // Progress
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

            // Document Preview Placeholder
            Container(
              width: double.infinity,
              height: 280,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE8E8E8)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(
                    Icons.insert_drive_file_outlined,
                    size: 48,
                    color: Colors.black12,
                  ),
                  SizedBox(height: 12),
                  Text(
                    "DOCUMENT PREVIEW",
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black26,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Tap below to sign this document",
                    style: TextStyle(fontSize: 11, color: Colors.black26),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Sign Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _signed || _isSigning ? null : _signDocument,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _signed
                      ? Colors.green
                      : const Color(0xFFCC0000),
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
                                : Icons.draw_outlined,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _signed ? "DOCUMENT SIGNED" : "SIGN DOCUMENT",
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
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "CANCEL AND GO BACK",
                  style: TextStyle(
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
