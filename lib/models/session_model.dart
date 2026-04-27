// lib/models/session_model.dart
class SessionModel {
  final int userId;
  final String firstName;
  final String accountType;
  final String access;
  final String? email;
  final String? passwordHash; // stored for offline re-login after QR scan
  final bool fromQr; // true = originally came from a QR scan

  SessionModel({
    required this.userId,
    required this.firstName,
    required this.accountType,
    required this.access,
    this.email,
    this.passwordHash,
    this.fromQr = false,
  });

  factory SessionModel.fromJson(Map<String, dynamic> json) => SessionModel(
        userId: json['user_id'] as int? ?? 0,
        firstName: json['first_name'] as String? ?? '',
        accountType: json['account_type'] as String? ?? '',
        access: json['access'] as String? ?? '',
        email: json['email'] as String?,
        passwordHash: json['password_hash'] as String?,
        fromQr: json['from_qr'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'first_name': firstName,
        'account_type': accountType,
        'access': access,
        'email': email,
        'password_hash': passwordHash,
        'from_qr': fromQr,
      };
}
