import 'package:flutter/material.dart';

import 'package:eforward_app/widgets/eforward_app_bar.dart';

/// A single titled section within a legal document.
///
/// [body] lines beginning with `• ` are rendered as bullet rows; all other
/// lines render as normal paragraphs.
class LegalSection {
  const LegalSection({required this.heading, required this.body});

  final String heading;
  final List<String> body;
}

/// Reusable, read-only scrollable page for long-form legal / informational
/// content (Privacy Policy, Terms of Service, etc.).
///
/// Kept generic so each document only has to supply its title, effective
/// date, intro and section list — matching the pattern of extracting shared
/// widgets like [EForwardAppBar] instead of copy-pasting the scaffold.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.appBarTitle,
    required this.documentTitle,
    required this.effectiveDate,
    required this.intro,
    required this.sections,
  });

  final String appBarTitle;
  final String documentTitle;
  final String effectiveDate;
  final List<String> intro;
  final List<LegalSection> sections;

  static const Color _red = Color(0xFFCC0000);
  static const Color _dark = Color(0xFF1A1A1A);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: EForwardAppBar(title: appBarTitle, backgroundColor: Colors.white),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title with red accent bar (matches Settings header treatment).
              Row(
                children: [
                  Container(width: 3, height: 20, color: _red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      documentTitle.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: _red,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Last updated: $effectiveDate',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: Color(0xFFAAAAAA),
                ),
              ),
              const SizedBox(height: 20),

              // Intro paragraphs.
              ...intro.map(_paragraph),

              // Sections.
              ...sections.map(_buildSection),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(LegalSection section) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          section.heading,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
            color: _dark,
          ),
        ),
        const SizedBox(height: 8),
        ...section.body.map((line) {
          if (line.startsWith('• ')) {
            return _bullet(line.substring(2));
          }
          return _paragraph(line);
        }),
      ],
    );
  }

  Widget _paragraph(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13.5,
          height: 1.55,
          color: Color(0xFF444444),
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 10),
            child: Icon(Icons.circle, size: 5, color: _red),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: Color(0xFF444444),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
