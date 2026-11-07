import '../../admin/domain/admin_user.dart';
import 'auth_user.dart';

/// Who a password sign-in let in. Sealed, so every caller has to say what
/// happens for an admin as well as for a trainee.
sealed class SignInOutcome {
  const SignInOutcome();
}

final class TraineeSignedIn extends SignInOutcome {
  const TraineeSignedIn(this.user);

  final AuthUser user;
}

final class AdminSignedIn extends SignInOutcome {
  const AdminSignedIn(this.admin);

  final AdminUser admin;
}
