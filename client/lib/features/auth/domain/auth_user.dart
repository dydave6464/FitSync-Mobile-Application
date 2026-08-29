class AuthUser {
  const AuthUser({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.onboardingCompleted,
    required this.isPremium,
  });

  final int userId;
  final String email;
  final String fullName;
  final bool onboardingCompleted;
  final bool isPremium;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        userId: json['userId'] as int,
        email: json['email'] as String,
        fullName: json['fullName'] as String,
        onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
        isPremium: json['isPremium'] as bool? ?? false,
      );
}
