import 'package:flutter/material.dart';
import 'package:eforward_app/validators/password_validator.dart';

enum PasswordStrength { empty, weak, medium, strong }

/// Live password strength meter: a right-aligned "Weak/Medium/Strong" label
/// over a fill bar, plus a row of requirement chips (length, case, digit,
/// symbol). Rebuild with the latest [password] on every keystroke (e.g. from
/// a `TextEditingController` listener) to animate in real time.
class PasswordStrengthIndicator extends StatelessWidget {
  final String password;

  const PasswordStrengthIndicator({super.key, required this.password});

  static const List<_Requirement> _requirements = [
    _Requirement('8 Chars', PasswordValidator.hasMinLength),
    _Requirement('A-Z', PasswordValidator.hasUppercase),
    _Requirement('a-z', PasswordValidator.hasLowercase),
    _Requirement('123', PasswordValidator.hasNumber),
    _Requirement('@#\$', PasswordValidator.hasSpecialChar),
  ];

  int get _score => _requirements.where((r) => r.isMet(password)).length;

  PasswordStrength get _strength {
    if (password.isEmpty) return PasswordStrength.empty;
    if (_score <= 1) return PasswordStrength.weak;
    if (_score <= 3) return PasswordStrength.medium;
    return PasswordStrength.strong;
  }

  Color get _strengthColor {
    switch (_strength) {
      case PasswordStrength.empty:
        return Colors.black12;
      case PasswordStrength.weak:
        return const Color(0xFFD32F2F);
      case PasswordStrength.medium:
        return const Color(0xFFF9A825);
      case PasswordStrength.strong:
        return const Color(0xFF2E7D32);
    }
  }

  String get _strengthLabel {
    switch (_strength) {
      case PasswordStrength.empty:
        return '';
      case PasswordStrength.weak:
        return 'Weak';
      case PasswordStrength.medium:
        return 'Medium';
      case PasswordStrength.strong:
        return 'Strong';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fraction = password.isEmpty ? 0.0 : _score / _requirements.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 16,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              _strengthLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: _strengthColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Container(height: 6, color: const Color(0xFFEEEEEE)),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    height: 6,
                    width: constraints.maxWidth * fraction,
                    color: _strengthColor,
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _requirements
              .map(
                (r) => _RequirementChip(label: r.label, met: r.isMet(password)),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _Requirement {
  final String label;
  final bool Function(String) isMet;

  const _Requirement(this.label, this.isMet);
}

class _RequirementChip extends StatelessWidget {
  final String label;
  final bool met;

  const _RequirementChip({required this.label, required this.met});

  @override
  Widget build(BuildContext context) {
    const metColor = Color(0xFF2E7D32);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: met ? const Color(0xFFE8F5E9) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: met ? metColor : const Color(0xFFEEEEEE),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: met ? metColor : Colors.transparent,
              border: Border.all(
                color: met ? metColor : Colors.black26,
                width: 1.3,
              ),
            ),
            child: met
                ? const Icon(Icons.check, size: 8, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: met ? const Color(0xFF1A1A1A) : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }
}
