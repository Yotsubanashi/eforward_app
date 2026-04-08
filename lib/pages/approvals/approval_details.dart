import 'package:flutter/material.dart';

class ApprovalDetailPage extends StatefulWidget {
  final Map<String, dynamic> item;

  const ApprovalDetailPage({super.key, required this.item});

  @override
  State<ApprovalDetailPage> createState() => _ApprovalDetailPageState();
}

class _ApprovalDetailPageState extends State<ApprovalDetailPage> {
  bool _isSigning = false;
  final TextEditingController _remarksController = TextEditingController();

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  void _showSignatureDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "SIGN DOCUMENT",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close,
                      size: 18, color: Colors.black45),
                ),
              ],
            ),

            const SizedBox(height: 4),
            const Text(
              "Your saved signature will be applied to this document.",
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),

            const SizedBox(height: 24),

            // Remarks field
            const Text(
              "REMARKS",
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: Colors.black45,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _remarksController,
              maxLines: 3,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF1A1A1A)),
              decoration: InputDecoration(
                hintText: "Enter your remarks (optional)...",
                hintStyle:
                    const TextStyle(color: Colors.black26, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFFF8F8F8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide:
                      const BorderSide(color: Color(0xFFE0E0E0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide:
                      const BorderSide(color: Color(0xFFE0E0E0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide:
                      const BorderSide(color: Color(0xFFCC0000)),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Approve button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSigning
                    ? null
                    : () {
                        setState(() => _isSigning = true);
                        Navigator.pop(context);
                        // TODO: call approveDocument API
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Document signed successfully!"),
                            backgroundColor: Colors.green,
                          ),
                        );
                        setState(() => _isSigning = false);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFCC0000),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.draw_outlined,
                        color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text(
                      "APPROVE & SIGN",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Request revision button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  // TODO: call requestRevision API
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Revision requested."),
                      backgroundColor: Colors.orange,
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFCC0000)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.refresh_outlined,
                        color: Color(0xFFCC0000), size: 16),
                    SizedBox(width: 8),
                    Text(
                      "REQUEST REVISION",
                      style: TextStyle(
                        color: Color(0xFFCC0000),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back,
              color: Color(0xFF1A1A1A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "APPROVAL DETAILS",
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
                Icon(Icons.shield_outlined,
                    color: Color(0xFFCC0000), size: 16),
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

            // Status badge + Reference No
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCC0000).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    "PENDING",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: Color(0xFFCC0000),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  item['referenceNo'] ?? item['id'] ?? '—',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFCC0000),
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Title
            Text(
              item['particulars'] ?? item['title'] ?? 'Document',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                color: Color(0xFF1A1A1A),
                height: 1.2,
              ),
            ),

            const SizedBox(height: 20),

            // Info Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE8E8E8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "DOCUMENT INFORMATION",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    Icons.person_outline,
                    "REQUESTER",
                    item['requester'] ?? item['createdBy'] ?? '—',
                  ),
                  const Divider(height: 24, color: Color(0xFFF0F0F0)),
                  _buildInfoRow(
                    Icons.calendar_today_outlined,
                    "DATE SENT",
                    item['dateSent'] ?? item['dateTime'] ?? '—',
                  ),
                  const Divider(height: 24, color: Color(0xFFF0F0F0)),
                  _buildInfoRow(
                    Icons.label_outline,
                    "CATEGORY",
                    item['label'] ?? item['category'] ?? '—',
                  ),
                  const Divider(height: 24, color: Color(0xFFF0F0F0)),
                  _buildInfoRow(
                    Icons.tag,
                    "REFERENCE NO",
                    item['referenceNo'] ?? item['id'] ?? '—',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Document Preview placeholder
            Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE8E8E8)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.picture_as_pdf_outlined,
                      size: 48, color: Colors.black12),
                  SizedBox(height: 12),
                  Text(
                    "DOCUMENT PREVIEW",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: Colors.black26,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Tap to view attached document",
                    style:
                        TextStyle(fontSize: 11, color: Colors.black26),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Legal notice
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  left: BorderSide(color: Color(0xFFCC0000), width: 3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.info_outline,
                      color: Color(0xFFCC0000), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "By signing this document, you confirm that you have reviewed all contents and authorize the action. This signature is legally binding.",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 80),
          ],
        ),
      ),

      // Bottom Sign Button
      bottomNavigationBar: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _showSignatureDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFCC0000),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.draw_outlined, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Text(
                  "SIGN DOCUMENT",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.black38),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: Colors.black38,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ],
        ),
      ],
    );
  }
}