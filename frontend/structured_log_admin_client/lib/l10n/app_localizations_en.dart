// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get auditActionUserCreated => 'User created';

  @override
  String get auditActionUserUpdated => 'User updated';

  @override
  String get auditActionUserBlocked => 'User blocked';

  @override
  String get auditActionUserUnblocked => 'User unblocked';

  @override
  String get auditActionUserDeleted => 'User deleted';

  @override
  String get auditActionGroupCreated => 'Group created';

  @override
  String get auditActionTeamCreated => 'Team created';

  @override
  String get auditActionTeamMemberAdded => 'Member added to team';

  @override
  String get auditActionTeamMemberRemoved => 'Member removed from team';

  @override
  String get auditActionProjectCreated => 'Project created';

  @override
  String get auditActionProjectQuotaUpdated => 'Project quota changed';

  @override
  String get auditActionProjectBlocked => 'Project blocked';

  @override
  String get auditActionProjectUnblocked => 'Project unblocked';

  @override
  String get auditActionSecretKeyCreated => 'Secret key created';

  @override
  String get auditActionSecretKeyRevoked => 'Secret key revoked';

  @override
  String get auditActionRoleAssignmentCreated => 'Role granted';

  @override
  String get auditActionRoleAssignmentRevoked => 'Role revoked';

  @override
  String get auditActionPasswordChanged => 'Password changed';

  @override
  String get auditActionPasswordResetConfirmed => 'Password reset';

  @override
  String get auditActionEmailVerified => 'Email verified';

  @override
  String get auditActionAuthLoginSucceeded => 'Signed in';

  @override
  String get auditActionAuthLoginFailed => 'Failed sign-in attempt';

  @override
  String get auditActionAuthLoggedOut => 'Signed out';

  @override
  String get auditActionAuthThrottled => 'Requests throttled';

  @override
  String get auditActionAuditPurged => 'Audit purged';

  @override
  String get auditTargetUser => 'user';

  @override
  String get auditTargetGroup => 'group';

  @override
  String get auditTargetTeam => 'team';

  @override
  String get auditTargetProject => 'project';

  @override
  String get auditTargetSecretKey => 'key';

  @override
  String get auditTargetRoleAssignment => 'role assignment';

  @override
  String get auditTargetAuth => 'authentication';

  @override
  String get auditTargetAudit => 'audit';

  @override
  String auditTargetWithId(String name, int id) {
    return '$name #$id';
  }

  @override
  String get auditActorUnknownUser => 'account does not exist';

  @override
  String get auditActorServer => 'server';

  @override
  String get auditFailureForbidden =>
      'The audit log is available to administrators only. It spans all groups and projects, so there is no partial access.';

  @override
  String get auditFailureInvalidRequest =>
      'The server rejected a request with these filters.';

  @override
  String get auditFailureNotFound =>
      'The audit endpoint is not available on this server.';

  @override
  String get auditFailureUnauthorized =>
      'Your session has expired. Sign in again.';

  @override
  String get auditFailureConflict =>
      'The server responded with a conflict. Try again.';

  @override
  String auditFailureRateLimited(int seconds) {
    return 'Too many requests. Try again in $seconds s.';
  }

  @override
  String get auditFailureNetwork =>
      'Server unavailable. Check your connection.';

  @override
  String auditFailureServer(int statusCode) {
    return 'The server responded with an error ($statusCode). Try again.';
  }

  @override
  String get auditRetentionForever => 'no time limit';

  @override
  String auditRetentionDays(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n days',
      one: '$n day',
    );
    return '$_temp0';
  }

  @override
  String get auditMetaNoChangesKey => 'changes';

  @override
  String get auditMetaNoChangesValue => 'none';

  @override
  String get auditMetaNoLimit => 'no limit';

  @override
  String get auditMetaYes => 'yes';

  @override
  String get auditMetaNo => 'no';

  @override
  String get auditTitle => 'Audit';

  @override
  String get auditSubtitle =>
      'Log of administrative actions and sign-ins — administrators only';

  @override
  String get auditFilterTargetId => 'Target ID';

  @override
  String get auditFilterActorId => 'Actor ID';

  @override
  String get auditFilterReset => 'Reset filters';

  @override
  String get auditFilterActionAny => 'Action: any';

  @override
  String get auditFilterTargetTypeAny => 'Target type: any';

  @override
  String get auditDateFrom => 'From';

  @override
  String get auditDateTo => 'To';

  @override
  String get auditDateAny => 'any';

  @override
  String get auditDateClear => 'Any date';

  @override
  String get auditLoadFailedTitle => 'Log not loaded';

  @override
  String get auditPurgedTitle => 'These records have already been deleted';

  @override
  String auditPurgedDescription(String authRetention, String auditRetention) {
    return 'The selected period is beyond the retention window: authentication events are kept for $authRetention, administrative actions for $auditRetention. This does not mean nothing happened.';
  }

  @override
  String get auditNothingFoundTitle => 'Nothing found';

  @override
  String get auditEmptyTitle => 'No records yet';

  @override
  String get auditNothingFoundDescription =>
      'No audit records match these filters — try changing the period or resetting the filters';

  @override
  String get auditEmptyDescription =>
      'Administrative actions and sign-ins will appear here as soon as they happen';

  @override
  String get auditLoadMore => 'Show more';

  @override
  String get auditColumnTime => 'Time';

  @override
  String get auditColumnActor => 'Actor';

  @override
  String get auditColumnAction => 'Action';

  @override
  String get auditColumnTarget => 'Target';

  @override
  String get auditColumnDetails => 'Details';

  @override
  String auditRetentionAdminTag(String retention) {
    return 'Administrative actions: $retention';
  }

  @override
  String auditRetentionAuthTag(String retention) {
    return 'Authentication events: $retention';
  }

  @override
  String get auditRetentionNote =>
      'Records older than the retention period are deleted automatically — each purge is recorded in the audit as audit.purged';

  @override
  String get authBrandSubtitle => 'Administration panel';

  @override
  String get authLoginBrandDescription =>
      'Centralized collection and search of structured logs from multiple projects and teams — without a third-party SaaS.';

  @override
  String get authLoginTitle => 'Sign in';

  @override
  String get authLoginSubtitle =>
      'Enter the credentials issued by your administrator';

  @override
  String get authSessionExpiredBanner =>
      'Session ended — please sign in again. This happens when an administrator changed your permissions or the session expired.';

  @override
  String get authUsernameLabel => 'Username';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String authServerLine(String host) {
    return 'Server: $host';
  }

  @override
  String get authSubmittingLabel => 'Signing in…';

  @override
  String authSignInWithWait(String wait) {
    return 'Sign in · $wait';
  }

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authInvalidCredentials =>
      'Incorrect username or password. Please try again.';

  @override
  String get authEmailNotVerified =>
      'This account\'s email has not been verified yet — signing in is not possible until it is. Check your email for the code.';

  @override
  String authRateLimited(String wait) {
    return 'Too many sign-in attempts. The next one will be accepted in $wait.';
  }

  @override
  String get authNetworkFailure =>
      'Could not reach the server. Check the server address and your network connection.';

  @override
  String get authUnexpectedFailure =>
      'Could not sign in — the server responded unexpectedly. Try again, and if it keeps happening, check the server log.';

  @override
  String get authForceBrandDescription =>
      'A password set by an administrator is always temporary. Until it is changed, the rest of the app is closed — only changing the password and signing out are available.';

  @override
  String get authForceTitle => 'Change your password';

  @override
  String get authForceIntro =>
      'Your password was set by an administrator, so it is considered temporary. Until it is changed, the other sections are unavailable.';

  @override
  String get authForceSubmit => 'Change password and continue';

  @override
  String get authSignedIn => 'Signed in';

  @override
  String authSignedInAs(String username) {
    return 'Signed in as $username';
  }

  @override
  String get authSignOut => 'Sign out';

  @override
  String get authChangedTitle => 'Password changed';

  @override
  String get authChangedBody =>
      'The temporary password is no longer valid. The rest of the app is available again.';

  @override
  String get authChangedContinue => 'Go to the app';

  @override
  String get authCurrentPasswordLabel => 'Current (temporary) password';

  @override
  String get authNewPasswordLabel => 'New password';

  @override
  String get authRepeatPasswordLabel => 'Repeat new password';

  @override
  String get authPasswordsMismatch => 'Passwords do not match';

  @override
  String get authChangeWrongCurrent =>
      'The current password is incorrect. Enter the one your administrator gave you.';

  @override
  String authChangeRateLimited(int seconds) {
    return 'Too many attempts. Try again in $seconds s.';
  }

  @override
  String get authChangeNetwork => 'Server unavailable. Check your connection.';

  @override
  String get authChangeUnexpected =>
      'Could not change the password. Please try again.';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get appTitle => 'Structured Log';

  @override
  String monthShort(String month) {
    String _temp0 = intl.Intl.selectLogic(month, {
      '1': 'Jan',
      '2': 'Feb',
      '3': 'Mar',
      '4': 'Apr',
      '5': 'May',
      '6': 'Jun',
      '7': 'Jul',
      '8': 'Aug',
      '9': 'Sep',
      '10': 'Oct',
      '11': 'Nov',
      '12': 'Dec',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String formatDateShort(int day, String month, int year) {
    return '$day $month $year';
  }

  @override
  String formatDayMonth(String day, String month) {
    return '$day $month';
  }

  @override
  String get dashTitle => 'Dashboard';

  @override
  String get dashLoadFailed => 'Could not load the dashboard';

  @override
  String dashGreeting(String username) {
    return 'Hello, $username';
  }

  @override
  String get dashSubtitle =>
      'Administrator · quick access to what you manage and what you can view';

  @override
  String get dashAllGroups => 'Groups';

  @override
  String get dashShowAllGroups => 'Show all groups';

  @override
  String get dashNoGroups => 'No groups yet';

  @override
  String get dashNoGroupsHint =>
      'Groups will appear here as soon as someone creates them.';

  @override
  String get dashProjects => 'Projects';

  @override
  String get dashNoProjects => 'No projects yet';

  @override
  String get dashNoProjectsHint =>
      'Projects will appear here as soon as someone creates them inside a group.';

  @override
  String dashCreatedOn(String date) {
    return 'Created $date';
  }

  @override
  String get dashOpen => 'Open';

  @override
  String get dashEntries => 'Entries';

  @override
  String get dashViewLogs => 'View logs';

  @override
  String get logsScopesLoadFailed => 'Could not load the list of scopes';

  @override
  String get logsFailureRetryRefresh => 'Try refreshing the page.';

  @override
  String get logsFailureForbidden => 'You do not have access to this scope.';

  @override
  String get logsFailureNetwork =>
      'The server is unreachable. Check your connection.';

  @override
  String get logsFailureRetry => 'Try again.';

  @override
  String logsScopeProject(String name) {
    return 'Project: $name';
  }

  @override
  String logsScopeGroup(String name) {
    return 'Group: $name';
  }

  @override
  String get logsTitle => 'Logs';

  @override
  String get logsChangeScope => 'Change scope';

  @override
  String get logsSearchPlaceholder => 'Search by event';

  @override
  String get logsFilterCategory => 'Category';

  @override
  String get logsFilterLogger => 'Logger';

  @override
  String get logsTimeFrom => 'From';

  @override
  String get logsTimeTo => 'To';

  @override
  String get logsTimeAny => 'any';

  @override
  String get logsTimeAnyTime => 'Any time';

  @override
  String get logsTimeApply => 'Apply';

  @override
  String get logsAddCorrelationId => '+ correlation id';

  @override
  String get logsSearch => 'Search';

  @override
  String get logsReset => 'Reset';

  @override
  String get logsLivePaused => 'Paused';

  @override
  String get logsLiveRealtime => 'Live';

  @override
  String get logsResume => 'Resume';

  @override
  String get logsPause => 'Pause';

  @override
  String get logsLevelAny => 'Any level';

  @override
  String get logsLevelTrace => 'Trace and above';

  @override
  String get logsLevelDebug => 'Debug and above';

  @override
  String get logsLevelInfo => 'Info and above';

  @override
  String get logsLevelWarning => 'Warning and above';

  @override
  String get logsLevelError => 'Error and above';

  @override
  String get logsLevelCritical => 'Critical only';

  @override
  String get logsCorrelationDialogTitle => 'Filter by correlation id';

  @override
  String get logsCorrelationField => 'Field';

  @override
  String get logsCorrelationValue => 'Value';

  @override
  String get logsCorrelationNotNumber => 'The value must be a number';

  @override
  String get logsCancel => 'Cancel';

  @override
  String get logsAdd => 'Add';

  @override
  String get logsEmptyNoResultsTitle => 'Nothing found';

  @override
  String get logsEmptyNoEntriesTitle => 'No entries yet';

  @override
  String get logsEmptyNoResultsBody => 'No entry matches the current filters.';

  @override
  String get logsEmptyNoEntriesBody =>
      'As soon as the application sends its first entry, it will appear here.';

  @override
  String get logsLoadingOlder => 'Loading earlier entries…';

  @override
  String get logsStalledTitle => 'Live stream stopped';

  @override
  String get logsStalledProjectBlocked =>
      'The project is blocked, so no new entries arrive for it. What is shown below is left over from the last load.';

  @override
  String logsStalledClosed(String reason) {
    return 'The server closed the subscription ($reason). The list below is left over from the last load.';
  }

  @override
  String get logsReloadAndContinue => 'Reload and continue';

  @override
  String get logsLiveFeed => 'Live feed — new entries appear at the bottom';

  @override
  String logsUnseen(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new entries',
      one: '$count new entry',
    );
    return '$_temp0 · jump to latest';
  }

  @override
  String get logsPausedTooLong => 'Paused for too long';

  @override
  String get logsPausedOverflowBody =>
      'Some events did not fit in the buffer. Resuming reloads a fresh page in full instead of showing an incomplete list.';

  @override
  String logsPausedBuffered(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '$count entry',
    );
    return 'Feed paused · $_temp0 buffered';
  }

  @override
  String get logsBackToFeed => 'Back to feed';

  @override
  String get logsSelectEntryTitle => 'Select an entry';

  @override
  String get logsSelectEntryBody =>
      'The feed is on the left; here you will see the whole entry, including the custom fields the application sent.';

  @override
  String get logsNoScopesTitle => 'No scopes available';

  @override
  String get logsNoScopesBody =>
      'Logs are visible in the projects and groups where you have a role. Ask an administrator to grant access.';

  @override
  String get logsPickScopeTitle => 'Choose a scope';

  @override
  String get logsPickScopeBody =>
      'Logs are queried for a single project or a single group — not several combined.';

  @override
  String get logsProjects => 'Projects';

  @override
  String get logsGroups => 'Groups';

  @override
  String get logsBlocked => 'blocked';

  @override
  String get logsCopy => 'Copy';

  @override
  String get logsStandardFields => 'STANDARD FIELDS';

  @override
  String get logsContext => 'CONTEXT';

  @override
  String get resCancel => 'Cancel';

  @override
  String get resOpen => 'Open';

  @override
  String get resRevoke => 'Revoke';

  @override
  String get resClose => 'Close';

  @override
  String get resAdd => 'Add';

  @override
  String get resDelete => 'Remove';

  @override
  String get resSave => 'Save';

  @override
  String get resGroup => 'Group';

  @override
  String get resBlocked => 'Blocked';

  @override
  String get resActive => 'Active';

  @override
  String resGroupPrefix(String name) {
    return 'Group: $name';
  }

  @override
  String resProjectPrefix(String name) {
    return 'Project: $name';
  }

  @override
  String get resFailForbidden =>
      'Not enough permissions. This action is available to an administrator, and for projects inside a group also to its owner.';

  @override
  String get resFailConflict =>
      'That name is already taken. Choose another one.';

  @override
  String get resFailSoleGroupOwner =>
      'That would leave the group without an owner. Make someone else an owner first.';

  @override
  String get resFailInvalid => 'Check the fields you filled in.';

  @override
  String get resFailNotFound =>
      'Object not found — it may have been deleted already.';

  @override
  String get resFailUnauthorized => 'Your session has expired. Sign in again.';

  @override
  String resFailRateLimited(int seconds) {
    return 'Too many attempts. Try again in $seconds s.';
  }

  @override
  String get resFailNetwork =>
      'The server is unreachable. Check your connection.';

  @override
  String resFailServer(int status) {
    return 'The server responded with an error ($status). Try again.';
  }

  @override
  String resBytesMb(String count) {
    return '$count MB';
  }

  @override
  String resBytesKb(String count) {
    return '$count KB';
  }

  @override
  String resDaysCount(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '$days day',
    );
    return '$_temp0';
  }

  @override
  String resSubjectTeam(int id) {
    return 'Team #$id';
  }

  @override
  String resSubjectUser(int id) {
    return 'User #$id';
  }

  @override
  String resSubjectTeamGen(int id) {
    return 'team #$id';
  }

  @override
  String resSubjectUserGen(int id) {
    return 'user #$id';
  }

  @override
  String get resNoLimit => 'no limit';

  @override
  String get resFieldRetention => 'Retention period, days (retention_days)';

  @override
  String get resFieldMaxEntries => 'Entry limit (max_entries)';

  @override
  String get resFieldMaxBytes => 'Size limit, MB (max_bytes)';

  @override
  String get resNewProject => 'New project';

  @override
  String get resProjectNameLabel => 'Project name';

  @override
  String get resNewProjectNote =>
      'The secret key for log ingestion is created separately, on the project screen, after the project is created.';

  @override
  String get resCreateProject => 'Create project';

  @override
  String get resEditQuota => 'Change quota';

  @override
  String get resKeyCreated => 'Key created';

  @override
  String resKeyRevealSubtitle(String project, String label) {
    return 'Project $project · label “$label”';
  }

  @override
  String get resKeyRevealWarning =>
      'The value is shown only once. After you close this window it will not be available anywhere — save it now.';

  @override
  String get resKeySavedClose => 'I have saved the key — close';

  @override
  String get resGrantAccess => 'Grant access';

  @override
  String get resGrant => 'Grant';

  @override
  String get resRecipient => 'Recipient';

  @override
  String get resUser => 'User';

  @override
  String get resTeam => 'Team';

  @override
  String get resRecipientName => 'Recipient name';

  @override
  String get resSearchUserHint => 'Start typing a username…';

  @override
  String get resSearchTeamHint => 'Start typing a team name…';

  @override
  String get resRole => 'Role';

  @override
  String resTeamMembersTitle(String team) {
    return 'Members of team “$team”';
  }

  @override
  String get resAddMember => 'Add member';

  @override
  String get resNoMembers => 'No members yet';

  @override
  String get resNoMembersHint => 'Add the first one using the search above.';

  @override
  String get resGroups => 'Groups';

  @override
  String get resCreateGroup => 'Create group';

  @override
  String get resGroupsLoadFailed => 'Could not load groups';

  @override
  String get commonSearchTruncated =>
      'Showing the first matches — type more to narrow it down';

  @override
  String get resShowMore => 'Show more';

  @override
  String get resNoGroups => 'No groups yet';

  @override
  String get resNoGroupsHint =>
      'A group owns projects. Create the first one to add a project to it and start receiving logs.';

  @override
  String get resNoGroupsHintReader =>
      'You do not have access to any group yet. An administrator can give you a role in one.';

  @override
  String resCreatedOn(String date) {
    return 'Created $date';
  }

  @override
  String resKeyCreatedOn(String date) {
    return 'Created $date';
  }

  @override
  String resKeyRevokedOn(String date) {
    return 'Revoked $date';
  }

  @override
  String get resNewGroup => 'New group';

  @override
  String get resGroupNameLabel => 'Group name';

  @override
  String get resNewGroupNote =>
      'A new group has no owner — grant the owner role to a user or a team on the group screen.';

  @override
  String get resTeams => 'Teams';

  @override
  String get resNoTeams => 'No teams yet';

  @override
  String get resNoTeamsHint =>
      'A team lets you grant a role to several users at once — all of its current members.';

  @override
  String get resMembers => 'Members';

  @override
  String get resNewTeam => 'New team';

  @override
  String get resTeamNameLabel => 'Team name';

  @override
  String get resCreateTeam => 'Create team';

  @override
  String get resNewTeamNote =>
      'A new team is empty — add members on the “Team members” screen.';

  @override
  String get resProjectShort => 'Project';

  @override
  String get resProjects => 'Projects';

  @override
  String get resProjectsLoadFailed => 'Could not load projects';

  @override
  String get resNoProjects => 'No projects yet';

  @override
  String get resNoProjectsHint =>
      'Create the first one — it will receive logs using a secret key.';

  @override
  String get resQuotaNoEntryLimit => 'no entry limit';

  @override
  String resQuotaEntryLimit(String count) {
    return 'limit of $count entries';
  }

  @override
  String resQuotaLine(String entries, String days) {
    return '$entries · retention $days';
  }

  @override
  String get resAccess => 'Access';

  @override
  String get resNoAccess => 'No access granted to anyone yet';

  @override
  String get resNoAccessGroupHint =>
      'Grant the owner or user role to open access to this group and its projects.';

  @override
  String get resNoAccessProjectHint =>
      'Grant the owner or user role to open access to this project.';

  @override
  String resRevokeAccessTitle(String subject) {
    return 'Revoke access from “$subject”?';
  }

  @override
  String resRevokeRoleGroup(String role) {
    return 'The “$role” role on this group will be revoked immediately.';
  }

  @override
  String resRevokeRoleProject(String role) {
    return 'The “$role” role on this project will be revoked immediately.';
  }

  @override
  String get resProjectLoadFailed => 'Could not load the project';

  @override
  String get resTryAgain => 'Try again.';

  @override
  String get resProjectBlockedBanner =>
      'The project is blocked by an administrator: ingesting new logs and reading this project\'s stored logs are disabled until it is unblocked. The project\'s secret keys are not revoked.';

  @override
  String get resBlock => 'Block';

  @override
  String get resUnblock => 'Unblock';

  @override
  String get resOpenLogs => 'Open logs';

  @override
  String resBlockTitle(String name) {
    return 'Block project “$name”?';
  }

  @override
  String get resBlockMessage =>
      'Ingesting new logs and reading this project\'s stored logs will be disabled until it is unblocked. The project\'s secret keys are not revoked.';

  @override
  String get resQuotaAndUsage => 'Quota and usage';

  @override
  String get resRetentionRow => 'Retention period (retention_days)';

  @override
  String get resEntriesBar => 'Entries (max_entries)';

  @override
  String get resSizeBar => 'Size (max_bytes)';

  @override
  String get resSecretKeys => 'Project secret keys';

  @override
  String get resCreateKey => 'Create key';

  @override
  String get resNoKeys => 'No secret keys yet';

  @override
  String get resNoKeysHint =>
      'Create the first one so that an application can send logs.';

  @override
  String get resNewKey => 'New secret key';

  @override
  String get resKeyLabelField => 'Label';

  @override
  String get resNewKeyNote =>
      'The label helps you tell later which application uses it. The key value will be shown once.';

  @override
  String resRevokeKeyTitle(String label) {
    return 'Revoke key “$label”?';
  }

  @override
  String get resRevokeKeyMessage =>
      'Applications that send logs with this key will be refused immediately. Revoking cannot be undone — create a new key if needed.';

  @override
  String get shellNavOverview => 'Overview';

  @override
  String get shellNavDashboard => 'Dashboard';

  @override
  String get shellNavAdministration => 'Administration';

  @override
  String get shellNavGroups => 'Groups';

  @override
  String get shellNavUsers => 'Users';

  @override
  String get shellNavAudit => 'Audit';

  @override
  String get shellNavLogs => 'Logs';

  @override
  String get shellNavLogSearch => 'Log search';

  @override
  String get shellAccountFallback => 'Account';

  @override
  String get shellRoleAdmin => 'Administrator';

  @override
  String get shellRoleUser => 'User';

  @override
  String get shellAccountSettings => 'Account settings';

  @override
  String get shellSignOut => 'Sign out';

  @override
  String get shellDeleteInvalidPassword => 'The current password is incorrect.';

  @override
  String get shellDeletePrimaryAdmin =>
      'The primary administrator cannot be deleted — this account is protected permanently.';

  @override
  String shellRateLimited(int seconds) {
    return 'Too many attempts. Try again in $seconds s.';
  }

  @override
  String get shellNetworkFailure =>
      'The server is unreachable. Check your connection.';

  @override
  String get shellDeleteFailed => 'Could not delete the account. Try again.';

  @override
  String get shellDeleteTitle => 'Delete account?';

  @override
  String get shellDeleteMessage =>
      'This cannot be undone. Your account will be blocked permanently and all current sessions ended immediately. The username stays reserved.';

  @override
  String get shellDeleteConfirm => 'Delete account';

  @override
  String get shellDeletePasswordLabel => 'Confirm with your current password';

  @override
  String get shellSettingsTitle => 'Account settings';

  @override
  String get shellSectionProfile => 'Profile';

  @override
  String get shellUsername => 'Username';

  @override
  String get shellEmail => 'Email';

  @override
  String get shellDisplayName => 'Display name';

  @override
  String get shellSectionSecurity => 'Security';

  @override
  String get shellPasswordChanged =>
      'Password changed. Your session is intact — you can keep working.';

  @override
  String get shellPasswordHintForm =>
      'The current password is required. Changing it does not end your session — you stay in the app.';

  @override
  String get shellChangePassword => 'Change password';

  @override
  String get shellPasswordHintRow =>
      'The current password is required. Changing it does not end your session.';

  @override
  String get shellSectionDanger => 'Danger zone';

  @override
  String get shellDeleteAccountTitle => 'Delete account';

  @override
  String get shellDeleteAccountText =>
      'Permanently deletes your account. All your sessions end immediately. This cannot be undone.';

  @override
  String get shellSectionLanguage => 'Language';

  @override
  String get shellLanguageHint =>
      'Interface language. Until you choose one, the app follows your browser.';

  @override
  String get shellLanguageSystem => 'Browser default';

  @override
  String get shellLanguageEnglish => 'English';

  @override
  String get shellLanguageRussian => 'Русский';

  @override
  String get usersFailureCannotDeletePrimaryAdmin =>
      'The primary administrator cannot be deleted — this account is protected permanently, no matter how many other administrators there are in the system.';

  @override
  String get usersFailureForbidden =>
      'Not enough permissions. This action is available to administrators only.';

  @override
  String get usersFailureUsernameTaken =>
      'This username is already taken. Choose another one.';

  @override
  String get usersFailureDeletedAccount =>
      'The account has been deleted and cannot be unblocked. Deletion is irreversible.';

  @override
  String get usersFailureSoleGroupOwner =>
      'The user is the only owner of one or more groups. Assign another owner first.';

  @override
  String get usersFailureConflict => 'Conflict while saving. Try again.';

  @override
  String get usersFailureSelfDeletion => 'You cannot delete yourself this way.';

  @override
  String get usersFailureInvalidRequest => 'Check the fields you filled in.';

  @override
  String get usersFailureNotFound =>
      'User not found — perhaps someone else has already deleted it.';

  @override
  String get usersFailureUnauthorized =>
      'Your session has expired. Sign in again.';

  @override
  String usersFailureRateLimited(int seconds) {
    return 'Too many attempts. Try again in $seconds s.';
  }

  @override
  String get usersFailureNetwork =>
      'The server is unavailable. Check your connection.';

  @override
  String usersFailureServer(int statusCode) {
    return 'The server responded with an error ($statusCode). Try again.';
  }

  @override
  String get usersPageTitle => 'Users';

  @override
  String get usersCreateUser => 'Create user';

  @override
  String get usersLoadFailedTitle => 'Could not load users';

  @override
  String get usersEmptyTitle => 'No users yet';

  @override
  String get usersEmptyDescription =>
      'Accounts will appear here as soon as you create the first one.';

  @override
  String get usersShowMore => 'Show more';

  @override
  String usersCreatedOn(String date) {
    return 'Created $date';
  }

  @override
  String get usersStatusDeleted => 'Deleted';

  @override
  String get usersStatusBlocked => 'Blocked';

  @override
  String get usersStatusActive => 'Active';

  @override
  String get usersPrimaryAdmin => 'Primary administrator';

  @override
  String get usersTemporaryPassword => 'Temporary password';

  @override
  String get usersOpen => 'Open';

  @override
  String get usersUnblock => 'Unblock';

  @override
  String get usersBlock => 'Block';

  @override
  String get usersDelete => 'Delete';

  @override
  String get usersCancel => 'Cancel';

  @override
  String get usersEditBreadcrumb => 'Edit';

  @override
  String get usersEditTitle => 'Edit account';

  @override
  String get usersEditSubtitle =>
      'Available to administrators only. This screen does not change the username or roles.';

  @override
  String get usersFieldUsername => 'Username';

  @override
  String get usersFieldEmail => 'Email';

  @override
  String get usersFieldDisplayName => 'Display name';

  @override
  String get usersNewPasswordLabel => 'New password (optional)';

  @override
  String get usersNewPasswordHint =>
      'Immediately ends the user\'s current session — at the next sign-in they will have to replace this password with their own.';

  @override
  String get usersFieldPassword => 'Password';

  @override
  String get usersKeepPassword => 'Leave unchanged';

  @override
  String get usersSaveChanges => 'Save changes';

  @override
  String get usersCreateDialogTitle => 'New user';

  @override
  String get usersFieldTemporaryPassword => 'Temporary password';

  @override
  String get usersFieldDisplayNameOptional => 'Display name (optional)';

  @override
  String get usersTemporaryPasswordHint =>
      'The user will have to change this password at first sign-in.';

  @override
  String usersBlockConfirmTitle(String username) {
    return 'Block \"$username\"?';
  }

  @override
  String get usersBlockConfirmMessage =>
      'The user\'s current session ends immediately. Signing in will be impossible until they are unblocked.';

  @override
  String usersDeleteConfirmTitle(String username) {
    return 'Delete \"$username\"?';
  }

  @override
  String get usersDeleteConfirmMessage =>
      'Irreversible: the account will cease to exist and all its sessions will end immediately. No password is asked for — this is your administrative action. Deletion cannot be undone; if needed you will have to create a new account.';

  @override
  String get usersSoleOwnerTitle => 'Transfer ownership first';

  @override
  String get usersSoleOwnerDescription =>
      'The user is the only owner of the following groups. Grant the owner role to someone else in each of them before the deletion becomes possible.';

  @override
  String get usersSoleOwnerTag => 'sole owner';

  @override
  String get usersGrantRole => 'Grant role';

  @override
  String get usersGotIt => 'Got it';

  @override
  String usersScopeGroupLabel(String name) {
    return 'group: $name';
  }

  @override
  String get usersPrimaryAdminBanner =>
      'This is the primary administrator account. It cannot be deleted — neither by another administrator nor by itself; the server rejects such a request with the code cannot_delete_primary_admin.';

  @override
  String get usersProfileTitle => 'Profile';

  @override
  String get usersFieldCreated => 'Created';

  @override
  String get usersSecurityTitle => 'Security';

  @override
  String get usersPasswordTemporary =>
      'Temporary — must be changed at next sign-in';

  @override
  String get usersPasswordSetByUser => 'Set by the user';

  @override
  String get usersRolesTitle => 'Roles';

  @override
  String get usersNoRoles => 'No roles granted yet.';

  @override
  String get usersRevoke => 'Revoke';

  @override
  String usersRevokeConfirmTitle(String role) {
    return 'Revoke the \"$role\" role?';
  }

  @override
  String usersRevokeConfirmMessage(String scope) {
    return 'Access ($scope) will be revoked immediately.';
  }

  @override
  String get usersScopeGlobal => 'entire system';

  @override
  String usersScopeProjectLabel(String name) {
    return 'project: $name';
  }

  @override
  String get usersScopeTypeGroup => 'Group';

  @override
  String get usersScopeTypeProject => 'Project';

  @override
  String get usersScopePickerPlaceholder => 'Start typing a name…';

  @override
  String get usersRecentAuditTitle => 'Recent audit events';

  @override
  String get usersNoAuditEvents => 'No events yet.';

  @override
  String get usersOpenInAudit =>
      'Open in the audit with a filter for this user';

  @override
  String get authCurrentPasswordLabelOwn => 'Current password';

  @override
  String get authChangeWrongCurrentOwn => 'The current password is incorrect.';

  @override
  String get usersSoleOwnerDescriptionSelf =>
      'You are the only owner of the following groups. Grant the owner role to someone else in each of them before the deletion becomes possible.';

  @override
  String commonPasswordTooShort(int min) {
    return 'The password must be at least $min characters.';
  }

  @override
  String commonPasswordTooLong(int max) {
    return 'The password is too long: at most $max bytes (a Cyrillic letter takes two).';
  }
}
