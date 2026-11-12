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
    this.hasPassword = true,
    this.hasGoogle = false,
  });

  final int userId;
  final String email;
  final String fullName;
  final bool onboardingCompleted;
  final bool isPremium;
  final bool emailVerified;

  /// Whether the account has a password: it decides between Change password
  /// and "You sign in with Google" in Settings, and what Delete account asks
  /// for to confirm it is the owner.
  final bool hasPassword;

  /// Whether a Google account is linked, so it can confirm a deletion.
  final bool hasGoogle;

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
    // A server from before account deletion sends neither. Every account it
    // knows has a password, and it links nothing to Google.
    hasPassword: json['hasPassword'] as bool? ?? true,
    hasGoogle: json['hasGoogle'] as bool? ?? false,
  );
}
