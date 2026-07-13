import 'package:flutter/material.dart';

import 'legal_document_screen.dart';

/// Privacy Policy shown in-app and required for App Store / Play Store review.
///
/// NOTE: App Store Connect and Google Play also require a *publicly hosted*
/// Privacy Policy URL. Keep this content in sync with the page published at
/// https://eforward.ardentnetworks.com.ph/privacy
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalDocumentScreen(
      appBarTitle: 'PRIVACY POLICY',
      documentTitle: 'Privacy Policy',
      effectiveDate: 'July 10, 2026',
      intro: [
        'E-Forward ("the App") is a document approval and electronic signature '
            'application provided by Ardent Networks Inc. ("we", "us", or "our"). '
            'This Privacy Policy explains what information we collect, how we use '
            'it, and the choices you have.',
        'By using the App you agree to the practices described in this policy.',
      ],
      sections: [
        LegalSection(
          heading: 'INFORMATION WE COLLECT',
          body: [
            '• Account information you provide, such as your name, work email '
                'address, employee ID, and role, used to authenticate you and '
                'associate documents with the correct approver.',
            '• Documents and signatures you upload, view, sign, or approve '
                'through the App.',
            '• Device information such as device model, operating system '
                'version, and a push-notification token used to deliver alerts.',
            '• Usage and diagnostic data to keep the service secure and '
                'reliable.',
          ],
        ),
        LegalSection(
          heading: 'HOW WE USE YOUR INFORMATION',
          body: [
            '• To authenticate you and provide the document approval and '
                'e-signature features of the App.',
            '• To send you notifications about documents awaiting your action '
                'and status updates.',
            '• To secure your account, prevent fraud, and troubleshoot issues.',
            '• To comply with legal, audit, and record-keeping obligations.',
          ],
        ),
        LegalSection(
          heading: 'DATA SHARING',
          body: [
            'We do not sell your personal information. Information is shared '
                'only within your organization as required to route and approve '
                'documents, and with service providers who process data on our '
                'behalf under confidentiality obligations (for example, cloud '
                'hosting and push-notification delivery).',
          ],
        ),
        LegalSection(
          heading: 'DATA SECURITY',
          body: [
            'We use industry-standard safeguards, including encrypted transport '
                '(HTTPS) and optional biometric / device-PIN app lock, to protect '
                'your information. Access is restricted to authorized users '
                'within your organization.',
          ],
        ),
        LegalSection(
          heading: 'DATA RETENTION',
          body: [
            'We retain your account information and documents for as long as '
                'your organization maintains an active account or as required by '
                'applicable law and audit requirements. You may request deletion '
                'through your organization administrator.',
          ],
        ),
        LegalSection(
          heading: 'YOUR RIGHTS',
          body: [
            'Subject to applicable law, you may request access to, correction '
                'of, or deletion of your personal information by contacting us or '
                'your organization administrator.',
          ],
        ),
        LegalSection(
          heading: "CHILDREN'S PRIVACY",
          body: [
            'The App is intended for business use by employees and authorized '
                'personnel and is not directed to children under 13.',
          ],
        ),
        LegalSection(
          heading: 'CHANGES TO THIS POLICY',
          body: [
            'We may update this Privacy Policy from time to time. Material '
                'changes will be reflected by updating the "Last updated" date '
                'above.',
          ],
        ),
        LegalSection(
          heading: 'CONTACT US',
          body: [
            'If you have questions about this Privacy Policy, contact us at:',
            'Ardent Networks Inc.',
            'Email: support@ardentnetworks.com.ph',
            'Website: https://eforward.ardentnetworks.com.ph',
          ],
        ),
      ],
    );
  }
}
