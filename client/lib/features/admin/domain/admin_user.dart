/// A FitSync admin, from the `admins` table: its own ids, never a trainee's.
class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    required this.fullName,
  });

  final int id;
  final String email;
  final String fullName;

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
    id: json['id'] as int,
    email: json['email'] as String,
    fullName: json['fullName'] as String,
  );
}
