class AuthUser {
  const AuthUser({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.onboardingCompleted,
    required this.isPremium,
    // Defaults to true rather than false: every existing call site builds
    // one from a session that is already signed in (login, /auth/me, a
    // fixture standing in for one of those), and under the hard verification
    // gate a signed-in user is by definition verified. `fromJson` below
    // makes the opposite, safer assumption for a value that actually came
    // over the wire.
    this.emailVerified = true,
  });

  final int userId;
  final String email;
  final String fullName;
  final bool onboardingCompleted;
  final bool isPremium;
  final bool emailVerified;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        userId: json['userId'] as int,
        email: json['email'] as String,
        fullName: json['fullName'] as String,
        onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
        isPremium: json['isPremium'] as bool? ?? false,
        // A missing field reads as "not verified" — the stricter assumption
        // is the safe one, since this value is never asked for once signed
        // in (see the class doc above).
        emailVerified: json['emailVerified'] as bool? ?? false,
      );
}
