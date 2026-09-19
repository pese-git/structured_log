import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'User created'**
  String get auditActionUserCreated;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'User updated'**
  String get auditActionUserUpdated;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'User blocked'**
  String get auditActionUserBlocked;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'User unblocked'**
  String get auditActionUserUnblocked;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'User deleted'**
  String get auditActionUserDeleted;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'Group created'**
  String get auditActionGroupCreated;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'Team created'**
  String get auditActionTeamCreated;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'Member added to team'**
  String get auditActionTeamMemberAdded;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'Member removed from team'**
  String get auditActionTeamMemberRemoved;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'Project created'**
  String get auditActionProjectCreated;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'Project quota changed'**
  String get auditActionProjectQuotaUpdated;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'Project blocked'**
  String get auditActionProjectBlocked;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'Project unblocked'**
  String get auditActionProjectUnblocked;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'Secret key created'**
  String get auditActionSecretKeyCreated;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'Secret key revoked'**
  String get auditActionSecretKeyRevoked;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'Role granted'**
  String get auditActionRoleAssignmentCreated;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'Role revoked'**
  String get auditActionRoleAssignmentRevoked;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'Password changed'**
  String get auditActionPasswordChanged;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'Password reset'**
  String get auditActionPasswordResetConfirmed;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'Email verified'**
  String get auditActionEmailVerified;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get auditActionAuthLoginSucceeded;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'Failed sign-in attempt'**
  String get auditActionAuthLoginFailed;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'Signed out'**
  String get auditActionAuthLoggedOut;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'Requests throttled'**
  String get auditActionAuthThrottled;

  /// Audit action display name
  ///
  /// In en, this message translates to:
  /// **'Audit purged'**
  String get auditActionAuditPurged;

  /// Audit target type name
  ///
  /// In en, this message translates to:
  /// **'user'**
  String get auditTargetUser;

  /// Audit target type name
  ///
  /// In en, this message translates to:
  /// **'group'**
  String get auditTargetGroup;

  /// Audit target type name
  ///
  /// In en, this message translates to:
  /// **'team'**
  String get auditTargetTeam;

  /// Audit target type name
  ///
  /// In en, this message translates to:
  /// **'project'**
  String get auditTargetProject;

  /// Audit target type name
  ///
  /// In en, this message translates to:
  /// **'key'**
  String get auditTargetSecretKey;

  /// Audit target type name
  ///
  /// In en, this message translates to:
  /// **'role assignment'**
  String get auditTargetRoleAssignment;

  /// Audit target type name
  ///
  /// In en, this message translates to:
  /// **'authentication'**
  String get auditTargetAuth;

  /// Audit target type name
  ///
  /// In en, this message translates to:
  /// **'audit'**
  String get auditTargetAudit;

  /// Target cell: type name and id
  ///
  /// In en, this message translates to:
  /// **'{name} #{id}'**
  String auditTargetWithId(String name, int id);

  /// Actor cell when login used a nonexistent username
  ///
  /// In en, this message translates to:
  /// **'account does not exist'**
  String get auditActorUnknownUser;

  /// Actor cell when the server itself acted
  ///
  /// In en, this message translates to:
  /// **'server'**
  String get auditActorServer;

  /// 403 on audit
  ///
  /// In en, this message translates to:
  /// **'The audit log is available to administrators only. It spans all groups and projects, so there is no partial access.'**
  String get auditFailureForbidden;

  /// 400 fallback
  ///
  /// In en, this message translates to:
  /// **'The server rejected a request with these filters.'**
  String get auditFailureInvalidRequest;

  /// 404
  ///
  /// In en, this message translates to:
  /// **'The audit endpoint is not available on this server.'**
  String get auditFailureNotFound;

  /// 401
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Sign in again.'**
  String get auditFailureUnauthorized;

  /// 409
  ///
  /// In en, this message translates to:
  /// **'The server responded with a conflict. Try again.'**
  String get auditFailureConflict;

  /// 429
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Try again in {seconds} s.'**
  String auditFailureRateLimited(int seconds);

  /// network
  ///
  /// In en, this message translates to:
  /// **'Server unavailable. Check your connection.'**
  String get auditFailureNetwork;

  /// 5xx
  ///
  /// In en, this message translates to:
  /// **'The server responded with an error ({statusCode}). Try again.'**
  String auditFailureServer(int statusCode);

  /// Retention: kept forever
  ///
  /// In en, this message translates to:
  /// **'no time limit'**
  String get auditRetentionForever;

  /// Retention period in days
  ///
  /// In en, this message translates to:
  /// **'{n, plural, one{{n} day} other{{n} days}}'**
  String auditRetentionDays(int n);

  /// Metadata key when before/after are equal
  ///
  /// In en, this message translates to:
  /// **'changes'**
  String get auditMetaNoChangesKey;

  /// Metadata value when nothing changed
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get auditMetaNoChangesValue;

  /// Quota null value
  ///
  /// In en, this message translates to:
  /// **'no limit'**
  String get auditMetaNoLimit;

  /// Boolean true
  ///
  /// In en, this message translates to:
  /// **'yes'**
  String get auditMetaYes;

  /// Boolean false
  ///
  /// In en, this message translates to:
  /// **'no'**
  String get auditMetaNo;

  /// Page title
  ///
  /// In en, this message translates to:
  /// **'Audit'**
  String get auditTitle;

  /// Page subtitle
  ///
  /// In en, this message translates to:
  /// **'Log of administrative actions and sign-ins — administrators only'**
  String get auditSubtitle;

  /// Placeholder
  ///
  /// In en, this message translates to:
  /// **'Target ID'**
  String get auditFilterTargetId;

  /// Placeholder
  ///
  /// In en, this message translates to:
  /// **'Actor ID'**
  String get auditFilterActorId;

  /// Button
  ///
  /// In en, this message translates to:
  /// **'Reset filters'**
  String get auditFilterReset;

  /// Combo placeholder
  ///
  /// In en, this message translates to:
  /// **'Action: any'**
  String get auditFilterActionAny;

  /// Combo placeholder
  ///
  /// In en, this message translates to:
  /// **'Target type: any'**
  String get auditFilterTargetTypeAny;

  /// Date range from label
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get auditDateFrom;

  /// Date range to label
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get auditDateTo;

  /// Date range unset
  ///
  /// In en, this message translates to:
  /// **'any'**
  String get auditDateAny;

  /// Date range clear
  ///
  /// In en, this message translates to:
  /// **'Any date'**
  String get auditDateClear;

  /// Empty state
  ///
  /// In en, this message translates to:
  /// **'Log not loaded'**
  String get auditLoadFailedTitle;

  /// Empty state
  ///
  /// In en, this message translates to:
  /// **'These records have already been deleted'**
  String get auditPurgedTitle;

  /// Empty state; retention values are localized phrases
  ///
  /// In en, this message translates to:
  /// **'The selected period is beyond the retention window: authentication events are kept for {authRetention}, administrative actions for {auditRetention}. This does not mean nothing happened.'**
  String auditPurgedDescription(String authRetention, String auditRetention);

  /// Empty state
  ///
  /// In en, this message translates to:
  /// **'Nothing found'**
  String get auditNothingFoundTitle;

  /// Empty state
  ///
  /// In en, this message translates to:
  /// **'No records yet'**
  String get auditEmptyTitle;

  /// Empty state
  ///
  /// In en, this message translates to:
  /// **'No audit records match these filters — try changing the period or resetting the filters'**
  String get auditNothingFoundDescription;

  /// Empty state
  ///
  /// In en, this message translates to:
  /// **'Administrative actions and sign-ins will appear here as soon as they happen'**
  String get auditEmptyDescription;

  /// Button
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get auditLoadMore;

  /// Column
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get auditColumnTime;

  /// Column
  ///
  /// In en, this message translates to:
  /// **'Actor'**
  String get auditColumnActor;

  /// Column
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get auditColumnAction;

  /// Column
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get auditColumnTarget;

  /// Column
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get auditColumnDetails;

  /// Retention tag
  ///
  /// In en, this message translates to:
  /// **'Administrative actions: {retention}'**
  String auditRetentionAdminTag(String retention);

  /// Retention tag
  ///
  /// In en, this message translates to:
  /// **'Authentication events: {retention}'**
  String auditRetentionAuthTag(String retention);

  /// Note
  ///
  /// In en, this message translates to:
  /// **'Records older than the retention period are deleted automatically — each purge is recorded in the audit as audit.purged'**
  String get auditRetentionNote;

  /// Brand panel subtitle under the product name
  ///
  /// In en, this message translates to:
  /// **'Administration panel'**
  String get authBrandSubtitle;

  /// Brand panel paragraph on the login screen
  ///
  /// In en, this message translates to:
  /// **'Centralized collection and search of structured logs from multiple projects and teams — without a third-party SaaS.'**
  String get authLoginBrandDescription;

  /// Login form title
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authLoginTitle;

  /// Login form subtitle
  ///
  /// In en, this message translates to:
  /// **'Enter the credentials issued by your administrator'**
  String get authLoginSubtitle;

  /// Banner shown when the session could not be renewed
  ///
  /// In en, this message translates to:
  /// **'Session ended — please sign in again. This happens when an administrator changed your permissions or the session expired.'**
  String get authSessionExpiredBanner;

  /// Username field label
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get authUsernameLabel;

  /// Password field label
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPasswordLabel;

  /// Server hostname line under the login form
  ///
  /// In en, this message translates to:
  /// **'Server: {host}'**
  String authServerLine(String host);

  /// Login button while request in flight
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get authSubmittingLabel;

  /// Login button while rate limiter counts down
  ///
  /// In en, this message translates to:
  /// **'Sign in · {wait}'**
  String authSignInWithWait(String wait);

  /// Login button
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignIn;

  /// Login failure: invalid credentials
  ///
  /// In en, this message translates to:
  /// **'Incorrect username or password. Please try again.'**
  String get authInvalidCredentials;

  /// Login failure: email not verified
  ///
  /// In en, this message translates to:
  /// **'This account\'s email has not been verified yet — signing in is not possible until it is. Check your email for the code.'**
  String get authEmailNotVerified;

  /// Login failure: rate limited
  ///
  /// In en, this message translates to:
  /// **'Too many sign-in attempts. The next one will be accepted in {wait}.'**
  String authRateLimited(String wait);

  /// Login failure: network
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server. Check the server address and your network connection.'**
  String get authNetworkFailure;

  /// Login failure: unexpected
  ///
  /// In en, this message translates to:
  /// **'Could not sign in — the server responded unexpectedly. Try again, and if it keeps happening, check the server log.'**
  String get authUnexpectedFailure;

  /// Brand panel paragraph on the forced password change screen
  ///
  /// In en, this message translates to:
  /// **'A password set by an administrator is always temporary. Until it is changed, the rest of the app is closed — only changing the password and signing out are available.'**
  String get authForceBrandDescription;

  /// Forced change screen title
  ///
  /// In en, this message translates to:
  /// **'Change your password'**
  String get authForceTitle;

  /// Forced change screen intro
  ///
  /// In en, this message translates to:
  /// **'Your password was set by an administrator, so it is considered temporary. Until it is changed, the other sections are unavailable.'**
  String get authForceIntro;

  /// Forced change submit button
  ///
  /// In en, this message translates to:
  /// **'Change password and continue'**
  String get authForceSubmit;

  /// Caption when username is unknown
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get authSignedIn;

  /// Caption with the username
  ///
  /// In en, this message translates to:
  /// **'Signed in as {username}'**
  String authSignedInAs(String username);

  /// Sign out link
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get authSignOut;

  /// Success title
  ///
  /// In en, this message translates to:
  /// **'Password changed'**
  String get authChangedTitle;

  /// Success body
  ///
  /// In en, this message translates to:
  /// **'The temporary password is no longer valid. The rest of the app is available again.'**
  String get authChangedBody;

  /// Success continue button
  ///
  /// In en, this message translates to:
  /// **'Go to the app'**
  String get authChangedContinue;

  /// Change form current password label
  ///
  /// In en, this message translates to:
  /// **'Current (temporary) password'**
  String get authCurrentPasswordLabel;

  /// Change form new password label
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get authNewPasswordLabel;

  /// Change form repeat label
  ///
  /// In en, this message translates to:
  /// **'Repeat new password'**
  String get authRepeatPasswordLabel;

  /// Mismatch field error
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get authPasswordsMismatch;

  /// Change failure: wrong current password
  ///
  /// In en, this message translates to:
  /// **'The current password is incorrect. Enter the one your administrator gave you.'**
  String get authChangeWrongCurrent;

  /// Change failure: rate limited
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again in {seconds} s.'**
  String authChangeRateLimited(int seconds);

  /// Change failure: network
  ///
  /// In en, this message translates to:
  /// **'Server unavailable. Check your connection.'**
  String get authChangeNetwork;

  /// Change failure: other
  ///
  /// In en, this message translates to:
  /// **'Could not change the password. Please try again.'**
  String get authChangeUnexpected;

  /// Cancel button of a confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Structured Log'**
  String get appTitle;

  /// Three-letter month abbreviation; month is 1-12 as a string
  ///
  /// In en, this message translates to:
  /// **'{month, select, 1{Jan} 2{Feb} 3{Mar} 4{Apr} 5{May} 6{Jun} 7{Jul} 8{Aug} 9{Sep} 10{Oct} 11{Nov} 12{Dec} other{}}'**
  String monthShort(String month);

  /// A date such as '14 Feb 2025'
  ///
  /// In en, this message translates to:
  /// **'{day} {month} {year}'**
  String formatDateShort(int day, String month, int year);

  /// A day and month such as '01 Sep'
  ///
  /// In en, this message translates to:
  /// **'{day} {month}'**
  String formatDayMonth(String day, String month);

  /// dashTitle
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashTitle;

  /// dashLoadFailed
  ///
  /// In en, this message translates to:
  /// **'Could not load the dashboard'**
  String get dashLoadFailed;

  /// dashGreeting
  ///
  /// In en, this message translates to:
  /// **'Hello, {username}'**
  String dashGreeting(String username);

  /// dashSubtitle
  ///
  /// In en, this message translates to:
  /// **'Administrator · quick access to what you manage and what you can view'**
  String get dashSubtitle;

  /// dashAllGroups
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get dashAllGroups;

  /// dashShowAllGroups
  ///
  /// In en, this message translates to:
  /// **'Show all groups'**
  String get dashShowAllGroups;

  /// dashNoGroups
  ///
  /// In en, this message translates to:
  /// **'No groups yet'**
  String get dashNoGroups;

  /// dashNoGroupsHint
  ///
  /// In en, this message translates to:
  /// **'Groups will appear here as soon as someone creates them.'**
  String get dashNoGroupsHint;

  /// dashProjects
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get dashProjects;

  /// dashNoProjects
  ///
  /// In en, this message translates to:
  /// **'No projects yet'**
  String get dashNoProjects;

  /// dashNoProjectsHint
  ///
  /// In en, this message translates to:
  /// **'Projects will appear here as soon as someone creates them inside a group.'**
  String get dashNoProjectsHint;

  /// dashCreatedOn
  ///
  /// In en, this message translates to:
  /// **'Created {date}'**
  String dashCreatedOn(String date);

  /// dashOpen
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get dashOpen;

  /// dashEntries
  ///
  /// In en, this message translates to:
  /// **'Entries'**
  String get dashEntries;

  /// dashViewLogs
  ///
  /// In en, this message translates to:
  /// **'View logs'**
  String get dashViewLogs;

  /// Empty-state title when the scope list fails to load
  ///
  /// In en, this message translates to:
  /// **'Could not load the list of scopes'**
  String get logsScopesLoadFailed;

  /// Scope load failure hint, unknown cause
  ///
  /// In en, this message translates to:
  /// **'Try refreshing the page.'**
  String get logsFailureRetryRefresh;

  /// Scope load failure: forbidden
  ///
  /// In en, this message translates to:
  /// **'You do not have access to this scope.'**
  String get logsFailureForbidden;

  /// Scope load failure: network
  ///
  /// In en, this message translates to:
  /// **'The server is unreachable. Check your connection.'**
  String get logsFailureNetwork;

  /// Scope load failure: generic
  ///
  /// In en, this message translates to:
  /// **'Try again.'**
  String get logsFailureRetry;

  /// Header pill for a project scope
  ///
  /// In en, this message translates to:
  /// **'Project: {name}'**
  String logsScopeProject(String name);

  /// Header pill for a group scope
  ///
  /// In en, this message translates to:
  /// **'Group: {name}'**
  String logsScopeGroup(String name);

  /// Page title
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get logsTitle;

  /// Button and tooltip returning to the scope selector
  ///
  /// In en, this message translates to:
  /// **'Change scope'**
  String get logsChangeScope;

  /// Search field placeholder
  ///
  /// In en, this message translates to:
  /// **'Search by event'**
  String get logsSearchPlaceholder;

  /// Filter chip label for category
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get logsFilterCategory;

  /// Filter chip label for logger
  ///
  /// In en, this message translates to:
  /// **'Logger'**
  String get logsFilterLogger;

  /// Time range: from label
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get logsTimeFrom;

  /// Time range: to label
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get logsTimeTo;

  /// Time range: unset bound
  ///
  /// In en, this message translates to:
  /// **'any'**
  String get logsTimeAny;

  /// Time range: clear action
  ///
  /// In en, this message translates to:
  /// **'Any time'**
  String get logsTimeAnyTime;

  /// Time range: apply action
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get logsTimeApply;

  /// Button opening the correlation id filter dialog
  ///
  /// In en, this message translates to:
  /// **'+ correlation id'**
  String get logsAddCorrelationId;

  /// Apply search button
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get logsSearch;

  /// Reset filters button
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get logsReset;

  /// Live pill while paused
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get logsLivePaused;

  /// Live pill while following
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get logsLiveRealtime;

  /// Resume live feed button
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get logsResume;

  /// Pause live feed button
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get logsPause;

  /// Level filter: no floor
  ///
  /// In en, this message translates to:
  /// **'Any level'**
  String get logsLevelAny;

  /// Level filter: trace floor
  ///
  /// In en, this message translates to:
  /// **'Trace and above'**
  String get logsLevelTrace;

  /// Level filter: debug floor
  ///
  /// In en, this message translates to:
  /// **'Debug and above'**
  String get logsLevelDebug;

  /// Level filter: info floor
  ///
  /// In en, this message translates to:
  /// **'Info and above'**
  String get logsLevelInfo;

  /// Level filter: warning floor
  ///
  /// In en, this message translates to:
  /// **'Warning and above'**
  String get logsLevelWarning;

  /// Level filter: error floor
  ///
  /// In en, this message translates to:
  /// **'Error and above'**
  String get logsLevelError;

  /// Level filter: critical only
  ///
  /// In en, this message translates to:
  /// **'Critical only'**
  String get logsLevelCritical;

  /// Correlation id dialog title
  ///
  /// In en, this message translates to:
  /// **'Filter by correlation id'**
  String get logsCorrelationDialogTitle;

  /// Correlation dialog: field selector label
  ///
  /// In en, this message translates to:
  /// **'Field'**
  String get logsCorrelationField;

  /// Correlation dialog: value input label
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get logsCorrelationValue;

  /// Correlation dialog: validation error for numeric field
  ///
  /// In en, this message translates to:
  /// **'The value must be a number'**
  String get logsCorrelationNotNumber;

  /// Dialog cancel button
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get logsCancel;

  /// Dialog add button
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get logsAdd;

  /// Feed empty state title with filters
  ///
  /// In en, this message translates to:
  /// **'Nothing found'**
  String get logsEmptyNoResultsTitle;

  /// Feed empty state title without filters
  ///
  /// In en, this message translates to:
  /// **'No entries yet'**
  String get logsEmptyNoEntriesTitle;

  /// Feed empty state body with filters
  ///
  /// In en, this message translates to:
  /// **'No entry matches the current filters.'**
  String get logsEmptyNoResultsBody;

  /// Feed empty state body without filters
  ///
  /// In en, this message translates to:
  /// **'As soon as the application sends its first entry, it will appear here.'**
  String get logsEmptyNoEntriesBody;

  /// Strip while an older page loads
  ///
  /// In en, this message translates to:
  /// **'Loading earlier entries…'**
  String get logsLoadingOlder;

  /// Strip: subscription ended
  ///
  /// In en, this message translates to:
  /// **'Live stream stopped'**
  String get logsStalledTitle;

  /// Strip description: project blocked
  ///
  /// In en, this message translates to:
  /// **'The project is blocked, so no new entries arrive for it. What is shown below is left over from the last load.'**
  String get logsStalledProjectBlocked;

  /// Strip description: server closed subscription
  ///
  /// In en, this message translates to:
  /// **'The server closed the subscription ({reason}). The list below is left over from the last load.'**
  String logsStalledClosed(String reason);

  /// Strip action: reload
  ///
  /// In en, this message translates to:
  /// **'Reload and continue'**
  String get logsReloadAndContinue;

  /// Strip while following
  ///
  /// In en, this message translates to:
  /// **'Live feed — new entries appear at the bottom'**
  String get logsLiveFeed;

  /// Strip: entries arrived while scrolled up
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} new entry} other{{count} new entries}} · jump to latest'**
  String logsUnseen(int count);

  /// Strip: buffer overflowed while paused
  ///
  /// In en, this message translates to:
  /// **'Paused for too long'**
  String get logsPausedTooLong;

  /// Strip description: overflow
  ///
  /// In en, this message translates to:
  /// **'Some events did not fit in the buffer. Resuming reloads a fresh page in full instead of showing an incomplete list.'**
  String get logsPausedOverflowBody;

  /// Strip: paused with buffered entries
  ///
  /// In en, this message translates to:
  /// **'Feed paused · {count, plural, one{{count} entry} other{{count} entries}} buffered'**
  String logsPausedBuffered(int count);

  /// Narrow detail: back button
  ///
  /// In en, this message translates to:
  /// **'Back to feed'**
  String get logsBackToFeed;

  /// Detail empty state title
  ///
  /// In en, this message translates to:
  /// **'Select an entry'**
  String get logsSelectEntryTitle;

  /// Detail empty state body
  ///
  /// In en, this message translates to:
  /// **'The feed is on the left; here you will see the whole entry, including the custom fields the application sent.'**
  String get logsSelectEntryBody;

  /// Scope selector empty state title
  ///
  /// In en, this message translates to:
  /// **'No scopes available'**
  String get logsNoScopesTitle;

  /// Scope selector empty state body
  ///
  /// In en, this message translates to:
  /// **'Logs are visible in the projects and groups where you have a role. Ask an administrator to grant access.'**
  String get logsNoScopesBody;

  /// Scope selector heading
  ///
  /// In en, this message translates to:
  /// **'Choose a scope'**
  String get logsPickScopeTitle;

  /// Scope selector explanation
  ///
  /// In en, this message translates to:
  /// **'Logs are queried for a single project or a single group — not several combined.'**
  String get logsPickScopeBody;

  /// Scope selector section title
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get logsProjects;

  /// Scope selector section title
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get logsGroups;

  /// Tag on a blocked project
  ///
  /// In en, this message translates to:
  /// **'blocked'**
  String get logsBlocked;

  /// Detail pane copy button
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get logsCopy;

  /// Detail pane section title
  ///
  /// In en, this message translates to:
  /// **'STANDARD FIELDS'**
  String get logsStandardFields;

  /// Detail pane section title
  ///
  /// In en, this message translates to:
  /// **'CONTEXT'**
  String get logsContext;

  /// resCancel
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get resCancel;

  /// resOpen
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get resOpen;

  /// resRevoke
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get resRevoke;

  /// resClose
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get resClose;

  /// resAdd
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get resAdd;

  /// resDelete
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get resDelete;

  /// resSave
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get resSave;

  /// resGroup
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get resGroup;

  /// resBlocked
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get resBlocked;

  /// resActive
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get resActive;

  /// resGroupPrefix
  ///
  /// In en, this message translates to:
  /// **'Group: {name}'**
  String resGroupPrefix(String name);

  /// resProjectPrefix
  ///
  /// In en, this message translates to:
  /// **'Project: {name}'**
  String resProjectPrefix(String name);

  /// resFailForbidden
  ///
  /// In en, this message translates to:
  /// **'Not enough permissions. This action is available to an administrator, and for projects inside a group also to its owner.'**
  String get resFailForbidden;

  /// resFailConflict
  ///
  /// In en, this message translates to:
  /// **'That name is already taken. Choose another one.'**
  String get resFailConflict;

  /// resFailInvalid
  ///
  /// In en, this message translates to:
  /// **'Check the fields you filled in.'**
  String get resFailInvalid;

  /// resFailNotFound
  ///
  /// In en, this message translates to:
  /// **'Object not found — it may have been deleted already.'**
  String get resFailNotFound;

  /// resFailUnauthorized
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Sign in again.'**
  String get resFailUnauthorized;

  /// resFailRateLimited
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again in {seconds} s.'**
  String resFailRateLimited(int seconds);

  /// resFailNetwork
  ///
  /// In en, this message translates to:
  /// **'The server is unreachable. Check your connection.'**
  String get resFailNetwork;

  /// resFailServer
  ///
  /// In en, this message translates to:
  /// **'The server responded with an error ({status}). Try again.'**
  String resFailServer(int status);

  /// resBytesMb
  ///
  /// In en, this message translates to:
  /// **'{count} MB'**
  String resBytesMb(String count);

  /// resBytesKb
  ///
  /// In en, this message translates to:
  /// **'{count} KB'**
  String resBytesKb(String count);

  /// resDaysCount
  ///
  /// In en, this message translates to:
  /// **'{days, plural, one{{days} day} other{{days} days}}'**
  String resDaysCount(int days);

  /// resSubjectTeam
  ///
  /// In en, this message translates to:
  /// **'Team #{id}'**
  String resSubjectTeam(int id);

  /// resSubjectUser
  ///
  /// In en, this message translates to:
  /// **'User #{id}'**
  String resSubjectUser(int id);

  /// resSubjectTeamGen
  ///
  /// In en, this message translates to:
  /// **'team #{id}'**
  String resSubjectTeamGen(int id);

  /// resSubjectUserGen
  ///
  /// In en, this message translates to:
  /// **'user #{id}'**
  String resSubjectUserGen(int id);

  /// resNoLimit
  ///
  /// In en, this message translates to:
  /// **'no limit'**
  String get resNoLimit;

  /// resFieldRetention
  ///
  /// In en, this message translates to:
  /// **'Retention period, days (retention_days)'**
  String get resFieldRetention;

  /// resFieldMaxEntries
  ///
  /// In en, this message translates to:
  /// **'Entry limit (max_entries)'**
  String get resFieldMaxEntries;

  /// resFieldMaxBytes
  ///
  /// In en, this message translates to:
  /// **'Size limit, MB (max_bytes)'**
  String get resFieldMaxBytes;

  /// resNewProject
  ///
  /// In en, this message translates to:
  /// **'New project'**
  String get resNewProject;

  /// resProjectNameLabel
  ///
  /// In en, this message translates to:
  /// **'Project name'**
  String get resProjectNameLabel;

  /// resNewProjectNote
  ///
  /// In en, this message translates to:
  /// **'The secret key for log ingestion is created separately, on the project screen, after the project is created.'**
  String get resNewProjectNote;

  /// resCreateProject
  ///
  /// In en, this message translates to:
  /// **'Create project'**
  String get resCreateProject;

  /// resEditQuota
  ///
  /// In en, this message translates to:
  /// **'Change quota'**
  String get resEditQuota;

  /// resKeyCreated
  ///
  /// In en, this message translates to:
  /// **'Key created'**
  String get resKeyCreated;

  /// resKeyRevealSubtitle
  ///
  /// In en, this message translates to:
  /// **'Project {project} · label “{label}”'**
  String resKeyRevealSubtitle(String project, String label);

  /// resKeyRevealWarning
  ///
  /// In en, this message translates to:
  /// **'The value is shown only once. After you close this window it will not be available anywhere — save it now.'**
  String get resKeyRevealWarning;

  /// resKeySavedClose
  ///
  /// In en, this message translates to:
  /// **'I have saved the key — close'**
  String get resKeySavedClose;

  /// resGrantAccess
  ///
  /// In en, this message translates to:
  /// **'Grant access'**
  String get resGrantAccess;

  /// resGrant
  ///
  /// In en, this message translates to:
  /// **'Grant'**
  String get resGrant;

  /// resRecipient
  ///
  /// In en, this message translates to:
  /// **'Recipient'**
  String get resRecipient;

  /// resUser
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get resUser;

  /// resTeam
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get resTeam;

  /// resRecipientName
  ///
  /// In en, this message translates to:
  /// **'Recipient name'**
  String get resRecipientName;

  /// resSearchUserHint
  ///
  /// In en, this message translates to:
  /// **'Start typing a username…'**
  String get resSearchUserHint;

  /// resSearchTeamHint
  ///
  /// In en, this message translates to:
  /// **'Start typing a team name…'**
  String get resSearchTeamHint;

  /// resRole
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get resRole;

  /// resTeamMembersTitle
  ///
  /// In en, this message translates to:
  /// **'Members of team “{team}”'**
  String resTeamMembersTitle(String team);

  /// resAddMember
  ///
  /// In en, this message translates to:
  /// **'Add member'**
  String get resAddMember;

  /// resNoMembers
  ///
  /// In en, this message translates to:
  /// **'No members yet'**
  String get resNoMembers;

  /// resNoMembersHint
  ///
  /// In en, this message translates to:
  /// **'Add the first one using the search above.'**
  String get resNoMembersHint;

  /// resGroups
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get resGroups;

  /// resCreateGroup
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get resCreateGroup;

  /// resGroupsLoadFailed
  ///
  /// In en, this message translates to:
  /// **'Could not load groups'**
  String get resGroupsLoadFailed;

  /// commonSearchTruncated
  ///
  /// In en, this message translates to:
  /// **'Showing the first matches — type more to narrow it down'**
  String get commonSearchTruncated;

  /// resShowMore
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get resShowMore;

  /// resNoGroups
  ///
  /// In en, this message translates to:
  /// **'No groups yet'**
  String get resNoGroups;

  /// resNoGroupsHint
  ///
  /// In en, this message translates to:
  /// **'A group owns projects. Create the first one to add a project to it and start receiving logs.'**
  String get resNoGroupsHint;

  /// resCreatedOn
  ///
  /// In en, this message translates to:
  /// **'Created {date}'**
  String resCreatedOn(String date);

  /// resKeyCreatedOn
  ///
  /// In en, this message translates to:
  /// **'Created {date}'**
  String resKeyCreatedOn(String date);

  /// resKeyRevokedOn
  ///
  /// In en, this message translates to:
  /// **'Revoked {date}'**
  String resKeyRevokedOn(String date);

  /// resNewGroup
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get resNewGroup;

  /// resGroupNameLabel
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get resGroupNameLabel;

  /// resNewGroupNote
  ///
  /// In en, this message translates to:
  /// **'A new group has no owner — grant the owner role to a user or a team on the group screen.'**
  String get resNewGroupNote;

  /// resTeams
  ///
  /// In en, this message translates to:
  /// **'Teams'**
  String get resTeams;

  /// resNoTeams
  ///
  /// In en, this message translates to:
  /// **'No teams yet'**
  String get resNoTeams;

  /// resNoTeamsHint
  ///
  /// In en, this message translates to:
  /// **'A team lets you grant a role to several users at once — all of its current members.'**
  String get resNoTeamsHint;

  /// resMembers
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get resMembers;

  /// resNewTeam
  ///
  /// In en, this message translates to:
  /// **'New team'**
  String get resNewTeam;

  /// resTeamNameLabel
  ///
  /// In en, this message translates to:
  /// **'Team name'**
  String get resTeamNameLabel;

  /// resCreateTeam
  ///
  /// In en, this message translates to:
  /// **'Create team'**
  String get resCreateTeam;

  /// resNewTeamNote
  ///
  /// In en, this message translates to:
  /// **'A new team is empty — add members on the “Team members” screen.'**
  String get resNewTeamNote;

  /// resProjectShort
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get resProjectShort;

  /// resProjects
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get resProjects;

  /// resProjectsLoadFailed
  ///
  /// In en, this message translates to:
  /// **'Could not load projects'**
  String get resProjectsLoadFailed;

  /// resNoProjects
  ///
  /// In en, this message translates to:
  /// **'No projects yet'**
  String get resNoProjects;

  /// resNoProjectsHint
  ///
  /// In en, this message translates to:
  /// **'Create the first one — it will receive logs using a secret key.'**
  String get resNoProjectsHint;

  /// resQuotaNoEntryLimit
  ///
  /// In en, this message translates to:
  /// **'no entry limit'**
  String get resQuotaNoEntryLimit;

  /// resQuotaEntryLimit
  ///
  /// In en, this message translates to:
  /// **'limit of {count} entries'**
  String resQuotaEntryLimit(String count);

  /// resQuotaLine
  ///
  /// In en, this message translates to:
  /// **'{entries} · retention {days}'**
  String resQuotaLine(String entries, String days);

  /// resAccess
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get resAccess;

  /// resNoAccess
  ///
  /// In en, this message translates to:
  /// **'No access granted to anyone yet'**
  String get resNoAccess;

  /// resNoAccessGroupHint
  ///
  /// In en, this message translates to:
  /// **'Grant the owner or user role to open access to this group and its projects.'**
  String get resNoAccessGroupHint;

  /// resNoAccessProjectHint
  ///
  /// In en, this message translates to:
  /// **'Grant the owner or user role to open access to this project.'**
  String get resNoAccessProjectHint;

  /// resRevokeAccessTitle
  ///
  /// In en, this message translates to:
  /// **'Revoke access from “{subject}”?'**
  String resRevokeAccessTitle(String subject);

  /// resRevokeRoleGroup
  ///
  /// In en, this message translates to:
  /// **'The “{role}” role on this group will be revoked immediately.'**
  String resRevokeRoleGroup(String role);

  /// resRevokeRoleProject
  ///
  /// In en, this message translates to:
  /// **'The “{role}” role on this project will be revoked immediately.'**
  String resRevokeRoleProject(String role);

  /// resProjectLoadFailed
  ///
  /// In en, this message translates to:
  /// **'Could not load the project'**
  String get resProjectLoadFailed;

  /// resTryAgain
  ///
  /// In en, this message translates to:
  /// **'Try again.'**
  String get resTryAgain;

  /// resProjectBlockedBanner
  ///
  /// In en, this message translates to:
  /// **'The project is blocked by an administrator: ingesting new logs and reading this project\'s stored logs are disabled until it is unblocked. The project\'s secret keys are not revoked.'**
  String get resProjectBlockedBanner;

  /// resBlock
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get resBlock;

  /// resUnblock
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get resUnblock;

  /// resOpenLogs
  ///
  /// In en, this message translates to:
  /// **'Open logs'**
  String get resOpenLogs;

  /// resBlockTitle
  ///
  /// In en, this message translates to:
  /// **'Block project “{name}”?'**
  String resBlockTitle(String name);

  /// resBlockMessage
  ///
  /// In en, this message translates to:
  /// **'Ingesting new logs and reading this project\'s stored logs will be disabled until it is unblocked. The project\'s secret keys are not revoked.'**
  String get resBlockMessage;

  /// resQuotaAndUsage
  ///
  /// In en, this message translates to:
  /// **'Quota and usage'**
  String get resQuotaAndUsage;

  /// resRetentionRow
  ///
  /// In en, this message translates to:
  /// **'Retention period (retention_days)'**
  String get resRetentionRow;

  /// resEntriesBar
  ///
  /// In en, this message translates to:
  /// **'Entries (max_entries)'**
  String get resEntriesBar;

  /// resSizeBar
  ///
  /// In en, this message translates to:
  /// **'Size (max_bytes)'**
  String get resSizeBar;

  /// resSecretKeys
  ///
  /// In en, this message translates to:
  /// **'Project secret keys'**
  String get resSecretKeys;

  /// resCreateKey
  ///
  /// In en, this message translates to:
  /// **'Create key'**
  String get resCreateKey;

  /// resNoKeys
  ///
  /// In en, this message translates to:
  /// **'No secret keys yet'**
  String get resNoKeys;

  /// resNoKeysHint
  ///
  /// In en, this message translates to:
  /// **'Create the first one so that an application can send logs.'**
  String get resNoKeysHint;

  /// resNewKey
  ///
  /// In en, this message translates to:
  /// **'New secret key'**
  String get resNewKey;

  /// resKeyLabelField
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get resKeyLabelField;

  /// resNewKeyNote
  ///
  /// In en, this message translates to:
  /// **'The label helps you tell later which application uses it. The key value will be shown once.'**
  String get resNewKeyNote;

  /// resRevokeKeyTitle
  ///
  /// In en, this message translates to:
  /// **'Revoke key “{label}”?'**
  String resRevokeKeyTitle(String label);

  /// resRevokeKeyMessage
  ///
  /// In en, this message translates to:
  /// **'Applications that send logs with this key will be refused immediately. Revoking cannot be undone — create a new key if needed.'**
  String get resRevokeKeyMessage;

  /// No description provided for @shellNavOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get shellNavOverview;

  /// No description provided for @shellNavDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get shellNavDashboard;

  /// No description provided for @shellNavAdministration.
  ///
  /// In en, this message translates to:
  /// **'Administration'**
  String get shellNavAdministration;

  /// No description provided for @shellNavGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get shellNavGroups;

  /// No description provided for @shellNavUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get shellNavUsers;

  /// No description provided for @shellNavAudit.
  ///
  /// In en, this message translates to:
  /// **'Audit'**
  String get shellNavAudit;

  /// No description provided for @shellNavLogs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get shellNavLogs;

  /// No description provided for @shellNavLogSearch.
  ///
  /// In en, this message translates to:
  /// **'Log search'**
  String get shellNavLogSearch;

  /// No description provided for @shellAccountFallback.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get shellAccountFallback;

  /// No description provided for @shellRoleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Administrator'**
  String get shellRoleAdmin;

  /// No description provided for @shellRoleUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get shellRoleUser;

  /// No description provided for @shellAccountSettings.
  ///
  /// In en, this message translates to:
  /// **'Account settings'**
  String get shellAccountSettings;

  /// No description provided for @shellSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get shellSignOut;

  /// No description provided for @shellDeleteInvalidPassword.
  ///
  /// In en, this message translates to:
  /// **'The current password is incorrect.'**
  String get shellDeleteInvalidPassword;

  /// No description provided for @shellDeletePrimaryAdmin.
  ///
  /// In en, this message translates to:
  /// **'The primary administrator cannot be deleted — this account is protected permanently.'**
  String get shellDeletePrimaryAdmin;

  /// No description provided for @shellRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again in {seconds} s.'**
  String shellRateLimited(int seconds);

  /// No description provided for @shellNetworkFailure.
  ///
  /// In en, this message translates to:
  /// **'The server is unreachable. Check your connection.'**
  String get shellNetworkFailure;

  /// No description provided for @shellDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete the account. Try again.'**
  String get shellDeleteFailed;

  /// No description provided for @shellDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete account?'**
  String get shellDeleteTitle;

  /// No description provided for @shellDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone. Your account will be blocked permanently and all current sessions ended immediately. The username stays reserved.'**
  String get shellDeleteMessage;

  /// No description provided for @shellDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get shellDeleteConfirm;

  /// No description provided for @shellDeletePasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm with your current password'**
  String get shellDeletePasswordLabel;

  /// No description provided for @shellSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Account settings'**
  String get shellSettingsTitle;

  /// No description provided for @shellSectionProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get shellSectionProfile;

  /// No description provided for @shellUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get shellUsername;

  /// No description provided for @shellEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get shellEmail;

  /// No description provided for @shellDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get shellDisplayName;

  /// No description provided for @shellSectionSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get shellSectionSecurity;

  /// No description provided for @shellPasswordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed. Your session is intact — you can keep working.'**
  String get shellPasswordChanged;

  /// No description provided for @shellPasswordHintForm.
  ///
  /// In en, this message translates to:
  /// **'The current password is required. Changing it does not end your session — you stay in the app.'**
  String get shellPasswordHintForm;

  /// No description provided for @shellChangePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get shellChangePassword;

  /// No description provided for @shellPasswordHintRow.
  ///
  /// In en, this message translates to:
  /// **'The current password is required. Changing it does not end your session.'**
  String get shellPasswordHintRow;

  /// No description provided for @shellSectionDanger.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get shellSectionDanger;

  /// No description provided for @shellDeleteAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get shellDeleteAccountTitle;

  /// No description provided for @shellDeleteAccountText.
  ///
  /// In en, this message translates to:
  /// **'Permanently deletes your account. All your sessions end immediately. This cannot be undone.'**
  String get shellDeleteAccountText;

  /// No description provided for @shellSectionLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get shellSectionLanguage;

  /// No description provided for @shellLanguageHint.
  ///
  /// In en, this message translates to:
  /// **'Interface language. Until you choose one, the app follows your browser.'**
  String get shellLanguageHint;

  /// No description provided for @shellLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'Browser default'**
  String get shellLanguageSystem;

  /// No description provided for @shellLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get shellLanguageEnglish;

  /// No description provided for @shellLanguageRussian.
  ///
  /// In en, this message translates to:
  /// **'Русский'**
  String get shellLanguageRussian;

  /// Users: 403 cannot_delete_primary_admin
  ///
  /// In en, this message translates to:
  /// **'The primary administrator cannot be deleted — this account is protected permanently, no matter how many other administrators there are in the system.'**
  String get usersFailureCannotDeletePrimaryAdmin;

  /// Users: 403
  ///
  /// In en, this message translates to:
  /// **'Not enough permissions. This action is available to administrators only.'**
  String get usersFailureForbidden;

  /// Users: 409 username_taken
  ///
  /// In en, this message translates to:
  /// **'This username is already taken. Choose another one.'**
  String get usersFailureUsernameTaken;

  /// Users: 409 deleted_account
  ///
  /// In en, this message translates to:
  /// **'The account has been deleted and cannot be unblocked. Deletion is irreversible.'**
  String get usersFailureDeletedAccount;

  /// Users: 409 sole_group_owner
  ///
  /// In en, this message translates to:
  /// **'The user is the only owner of one or more groups. Assign another owner first.'**
  String get usersFailureSoleGroupOwner;

  /// Users: other 409
  ///
  /// In en, this message translates to:
  /// **'Conflict while saving. Try again.'**
  String get usersFailureConflict;

  /// Users: 400 self_deletion_requires_me
  ///
  /// In en, this message translates to:
  /// **'You cannot delete yourself this way.'**
  String get usersFailureSelfDeletion;

  /// Users: 400 without server message
  ///
  /// In en, this message translates to:
  /// **'Check the fields you filled in.'**
  String get usersFailureInvalidRequest;

  /// Users: 404
  ///
  /// In en, this message translates to:
  /// **'User not found — perhaps someone else has already deleted it.'**
  String get usersFailureNotFound;

  /// Users: 401
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Sign in again.'**
  String get usersFailureUnauthorized;

  /// Users: 429
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again in {seconds} s.'**
  String usersFailureRateLimited(int seconds);

  /// Users: network failure
  ///
  /// In en, this message translates to:
  /// **'The server is unavailable. Check your connection.'**
  String get usersFailureNetwork;

  /// Users: 5xx
  ///
  /// In en, this message translates to:
  /// **'The server responded with an error ({statusCode}). Try again.'**
  String usersFailureServer(int statusCode);

  /// Users list title and breadcrumb root
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get usersPageTitle;

  /// Button and dialog confirm to create a user
  ///
  /// In en, this message translates to:
  /// **'Create user'**
  String get usersCreateUser;

  /// Users list error title
  ///
  /// In en, this message translates to:
  /// **'Could not load users'**
  String get usersLoadFailedTitle;

  /// Users list empty title
  ///
  /// In en, this message translates to:
  /// **'No users yet'**
  String get usersEmptyTitle;

  /// Users list empty description
  ///
  /// In en, this message translates to:
  /// **'Accounts will appear here as soon as you create the first one.'**
  String get usersEmptyDescription;

  /// Load more users button
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get usersShowMore;

  /// Subtitle with creation date
  ///
  /// In en, this message translates to:
  /// **'Created {date}'**
  String usersCreatedOn(String date);

  /// User status tag
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get usersStatusDeleted;

  /// User status tag
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get usersStatusBlocked;

  /// User status tag
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get usersStatusActive;

  /// Tag for the primary admin
  ///
  /// In en, this message translates to:
  /// **'Primary administrator'**
  String get usersPrimaryAdmin;

  /// Tag: user must change password
  ///
  /// In en, this message translates to:
  /// **'Temporary password'**
  String get usersTemporaryPassword;

  /// Row action
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get usersOpen;

  /// Button
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get usersUnblock;

  /// Button and confirm label
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get usersBlock;

  /// Button and confirm label
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get usersDelete;

  /// Cancel button in user dialogs and forms
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get usersCancel;

  /// Breadcrumb tail and edit button
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get usersEditBreadcrumb;

  /// Edit page title
  ///
  /// In en, this message translates to:
  /// **'Edit account'**
  String get usersEditTitle;

  /// Edit page hint
  ///
  /// In en, this message translates to:
  /// **'Available to administrators only. This screen does not change the username or roles.'**
  String get usersEditSubtitle;

  /// Field label
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usersFieldUsername;

  /// Field label
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get usersFieldEmail;

  /// Field label
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get usersFieldDisplayName;

  /// Edit page password section title
  ///
  /// In en, this message translates to:
  /// **'New password (optional)'**
  String get usersNewPasswordLabel;

  /// Edit page password hint
  ///
  /// In en, this message translates to:
  /// **'Immediately ends the user\'s current session — at the next sign-in they will have to replace this password with their own.'**
  String get usersNewPasswordHint;

  /// Field label
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get usersFieldPassword;

  /// Password placeholder
  ///
  /// In en, this message translates to:
  /// **'Leave unchanged'**
  String get usersKeepPassword;

  /// Edit page save button
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get usersSaveChanges;

  /// Create dialog title
  ///
  /// In en, this message translates to:
  /// **'New user'**
  String get usersCreateDialogTitle;

  /// Field label
  ///
  /// In en, this message translates to:
  /// **'Temporary password'**
  String get usersFieldTemporaryPassword;

  /// Field label
  ///
  /// In en, this message translates to:
  /// **'Display name (optional)'**
  String get usersFieldDisplayNameOptional;

  /// Create dialog hint
  ///
  /// In en, this message translates to:
  /// **'The user will have to change this password at first sign-in.'**
  String get usersTemporaryPasswordHint;

  /// Block confirmation title
  ///
  /// In en, this message translates to:
  /// **'Block \"{username}\"?'**
  String usersBlockConfirmTitle(String username);

  /// Block confirmation body
  ///
  /// In en, this message translates to:
  /// **'The user\'s current session ends immediately. Signing in will be impossible until they are unblocked.'**
  String get usersBlockConfirmMessage;

  /// Delete confirmation title
  ///
  /// In en, this message translates to:
  /// **'Delete \"{username}\"?'**
  String usersDeleteConfirmTitle(String username);

  /// Delete confirmation body
  ///
  /// In en, this message translates to:
  /// **'Irreversible: the account will cease to exist and all its sessions will end immediately. No password is asked for — this is your administrative action. Deletion cannot be undone; if needed you will have to create a new account.'**
  String get usersDeleteConfirmMessage;

  /// Sole owner dialog title
  ///
  /// In en, this message translates to:
  /// **'Transfer ownership first'**
  String get usersSoleOwnerTitle;

  /// Sole owner dialog body
  ///
  /// In en, this message translates to:
  /// **'The user is the only owner of the following groups. Grant the owner role to someone else in each of them before the deletion becomes possible.'**
  String get usersSoleOwnerDescription;

  /// Tag on a group row
  ///
  /// In en, this message translates to:
  /// **'sole owner'**
  String get usersSoleOwnerTag;

  /// Button
  ///
  /// In en, this message translates to:
  /// **'Grant role'**
  String get usersGrantRole;

  /// Dialog close button
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get usersGotIt;

  /// Scope of a role assignment and label passed to the grant-access dialog
  ///
  /// In en, this message translates to:
  /// **'group: {name}'**
  String usersScopeGroupLabel(String name);

  /// Banner on the primary admin's page
  ///
  /// In en, this message translates to:
  /// **'This is the primary administrator account. It cannot be deleted — neither by another administrator nor by itself; the server rejects such a request with the code cannot_delete_primary_admin.'**
  String get usersPrimaryAdminBanner;

  /// Card title
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get usersProfileTitle;

  /// Field label
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get usersFieldCreated;

  /// Card title
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get usersSecurityTitle;

  /// Password state
  ///
  /// In en, this message translates to:
  /// **'Temporary — must be changed at next sign-in'**
  String get usersPasswordTemporary;

  /// Password state
  ///
  /// In en, this message translates to:
  /// **'Set by the user'**
  String get usersPasswordSetByUser;

  /// Card title
  ///
  /// In en, this message translates to:
  /// **'Roles'**
  String get usersRolesTitle;

  /// Empty roles card
  ///
  /// In en, this message translates to:
  /// **'No roles granted yet.'**
  String get usersNoRoles;

  /// Button and confirm label
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get usersRevoke;

  /// Revoke confirmation title
  ///
  /// In en, this message translates to:
  /// **'Revoke the \"{role}\" role?'**
  String usersRevokeConfirmTitle(String role);

  /// Revoke confirmation body
  ///
  /// In en, this message translates to:
  /// **'Access ({scope}) will be revoked immediately.'**
  String usersRevokeConfirmMessage(String scope);

  /// Scope of a role assignment
  ///
  /// In en, this message translates to:
  /// **'entire system'**
  String get usersScopeGlobal;

  /// Scope of a role assignment
  ///
  /// In en, this message translates to:
  /// **'project: {name}'**
  String usersScopeProjectLabel(String name);

  /// Scope type option and picker label
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get usersScopeTypeGroup;

  /// Scope type option and picker label
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get usersScopeTypeProject;

  /// Group/project picker placeholder
  ///
  /// In en, this message translates to:
  /// **'Start typing a name…'**
  String get usersScopePickerPlaceholder;

  /// Card title
  ///
  /// In en, this message translates to:
  /// **'Recent audit events'**
  String get usersRecentAuditTitle;

  /// Empty audit card
  ///
  /// In en, this message translates to:
  /// **'No events yet.'**
  String get usersNoAuditEvents;

  /// Link
  ///
  /// In en, this message translates to:
  /// **'Open in the audit with a filter for this user'**
  String get usersOpenInAudit;

  /// Change form current password label when it is not a temporary one (account settings)
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get authCurrentPasswordLabelOwn;

  /// Change failure in account settings: wrong current password
  ///
  /// In en, this message translates to:
  /// **'The current password is incorrect.'**
  String get authChangeWrongCurrentOwn;

  /// Sole owner dialog body when the reader is deleting their own account
  ///
  /// In en, this message translates to:
  /// **'You are the only owner of the following groups. Grant the owner role to someone else in each of them before the deletion becomes possible.'**
  String get usersSoleOwnerDescriptionSelf;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
