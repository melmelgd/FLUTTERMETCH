class SessionModel {
  final int userId;
  final String firstName;
  final String accountType;
  final String access;

  SessionModel({
    required this.userId,
    required this.firstName,
    required this.accountType,
    required this.access,
  });

  factory SessionModel.fromJson(Map<String, dynamic> json) => SessionModel(
        userId: json['user_id'] as int? ?? 0,
        firstName: json['first_name'] as String? ?? '',
        accountType: json['account_type'] as String? ?? '',
        access: json['access'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'first_name': firstName,
        'account_type': accountType,
        'access': access,
      };
}
