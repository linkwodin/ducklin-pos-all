import '../l10n/app_localizations.dart';

String roleLabel(AppLocalizations l10n, String role) {
  switch (role) {
    case 'management':
      return l10n.roleManagement;
    case 'supervisor':
      return l10n.roleSupervisor;
    case 'pos_user':
      return l10n.rolePosUser;
    case 'cashier':
      return l10n.roleCashier;
    default:
      return l10n.roleStaff;
  }
}
