// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get auditActionUserCreated => 'Пользователь создан';

  @override
  String get auditActionUserUpdated => 'Пользователь изменён';

  @override
  String get auditActionUserBlocked => 'Пользователь заблокирован';

  @override
  String get auditActionUserUnblocked => 'Пользователь разблокирован';

  @override
  String get auditActionUserDeleted => 'Пользователь удалён';

  @override
  String get auditActionGroupCreated => 'Группа создана';

  @override
  String get auditActionTeamCreated => 'Команда создана';

  @override
  String get auditActionTeamMemberAdded => 'Участник добавлен в команду';

  @override
  String get auditActionTeamMemberRemoved => 'Участник исключён из команды';

  @override
  String get auditActionProjectCreated => 'Проект создан';

  @override
  String get auditActionProjectQuotaUpdated => 'Квота проекта изменена';

  @override
  String get auditActionProjectBlocked => 'Проект заблокирован';

  @override
  String get auditActionProjectUnblocked => 'Проект разблокирован';

  @override
  String get auditActionSecretKeyCreated => 'Секретный ключ создан';

  @override
  String get auditActionSecretKeyRevoked => 'Секретный ключ отозван';

  @override
  String get auditActionRoleAssignmentCreated => 'Роль выдана';

  @override
  String get auditActionRoleAssignmentRevoked => 'Роль отозвана';

  @override
  String get auditActionPasswordChanged => 'Пароль изменён';

  @override
  String get auditActionPasswordResetConfirmed => 'Пароль восстановлен';

  @override
  String get auditActionEmailVerified => 'Email подтверждён';

  @override
  String get auditActionAuthLoginSucceeded => 'Вход выполнен';

  @override
  String get auditActionAuthLoginFailed => 'Неудачная попытка входа';

  @override
  String get auditActionAuthLoggedOut => 'Выход';

  @override
  String get auditActionAuthThrottled => 'Запросы ограничены';

  @override
  String get auditActionAuditPurged => 'Очистка аудита';

  @override
  String get auditTargetUser => 'пользователь';

  @override
  String get auditTargetGroup => 'группа';

  @override
  String get auditTargetTeam => 'команда';

  @override
  String get auditTargetProject => 'проект';

  @override
  String get auditTargetSecretKey => 'ключ';

  @override
  String get auditTargetRoleAssignment => 'назначение роли';

  @override
  String get auditTargetAuth => 'аутентификация';

  @override
  String get auditTargetAudit => 'аудит';

  @override
  String auditTargetWithId(String name, int id) {
    return '$name #$id';
  }

  @override
  String get auditActorUnknownUser => 'учётной записи не существует';

  @override
  String get auditActorServer => 'сервер';

  @override
  String get auditFailureForbidden =>
      'Журнал аудита доступен только администратору. Он охватывает все группы и проекты, поэтому частичного доступа к нему нет.';

  @override
  String get auditFailureInvalidRequest =>
      'Сервер не принял запрос с такими фильтрами.';

  @override
  String get auditFailureNotFound =>
      'Эндпоинт аудита недоступен на этом сервере.';

  @override
  String get auditFailureUnauthorized => 'Сессия истекла. Войдите заново.';

  @override
  String get auditFailureConflict =>
      'Сервер ответил конфликтом. Повторите запрос.';

  @override
  String auditFailureRateLimited(int seconds) {
    return 'Слишком много запросов. Попробуйте через $seconds с.';
  }

  @override
  String get auditFailureNetwork => 'Сервер недоступен. Проверьте подключение.';

  @override
  String auditFailureServer(int statusCode) {
    return 'Сервер ответил ошибкой ($statusCode). Попробуйте ещё раз.';
  }

  @override
  String get auditRetentionForever => 'без ограничения срока';

  @override
  String auditRetentionDays(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n дней',
      many: '$n дней',
      few: '$n дня',
      one: '$n день',
    );
    return '$_temp0';
  }

  @override
  String get auditMetaNoChangesKey => 'изменений';

  @override
  String get auditMetaNoChangesValue => 'нет';

  @override
  String get auditMetaNoLimit => 'без лимита';

  @override
  String get auditMetaYes => 'да';

  @override
  String get auditMetaNo => 'нет';

  @override
  String get auditTitle => 'Аудит';

  @override
  String get auditSubtitle =>
      'Журнал административных действий и входов — доступен только администратору';

  @override
  String get auditFilterTargetId => 'ID цели';

  @override
  String get auditFilterActorId => 'ID инициатора';

  @override
  String get auditFilterReset => 'Сбросить фильтры';

  @override
  String get auditFilterActionAny => 'Действие: любое';

  @override
  String get auditFilterTargetTypeAny => 'Тип цели: любой';

  @override
  String get auditDateFrom => 'С';

  @override
  String get auditDateTo => 'По';

  @override
  String get auditDateAny => 'любая';

  @override
  String get auditDateClear => 'Любая дата';

  @override
  String get auditLoadFailedTitle => 'Журнал не загружен';

  @override
  String get auditPurgedTitle => 'Записи за этот период уже удалены';

  @override
  String auditPurgedDescription(String authRetention, String auditRetention) {
    return 'Выбранный период выходит за срок хранения: события аутентификации хранятся $authRetention, административные действия — $auditRetention. Это не значит, что событий не было.';
  }

  @override
  String get auditNothingFoundTitle => 'Ничего не найдено';

  @override
  String get auditEmptyTitle => 'Записей пока нет';

  @override
  String get auditNothingFoundDescription =>
      'По заданным фильтрам записей аудита нет — попробуйте изменить период или сбросить фильтры';

  @override
  String get auditEmptyDescription =>
      'Здесь появятся административные действия и входы, как только они произойдут';

  @override
  String get auditLoadMore => 'Показать ещё';

  @override
  String get auditColumnTime => 'Время';

  @override
  String get auditColumnActor => 'Инициатор';

  @override
  String get auditColumnAction => 'Действие';

  @override
  String get auditColumnTarget => 'Цель';

  @override
  String get auditColumnDetails => 'Детали';

  @override
  String auditRetentionAdminTag(String retention) {
    return 'Административные действия: $retention';
  }

  @override
  String auditRetentionAuthTag(String retention) {
    return 'События аутентификации: $retention';
  }

  @override
  String get auditRetentionNote =>
      'Записи старше срока удаляются автоматически — каждая такая очистка попадает в аудит как audit.purged';

  @override
  String get authBrandSubtitle => 'Панель администрирования';

  @override
  String get authLoginBrandDescription =>
      'Централизованный сбор и поиск структурированных логов с нескольких проектов и команд — без стороннего SaaS.';

  @override
  String get authLoginTitle => 'Вход в систему';

  @override
  String get authLoginSubtitle =>
      'Введите учётные данные, выданные администратором';

  @override
  String get authSessionExpiredBanner =>
      'Сессия завершена — войдите снова. Так бывает, когда администратор изменил права или истёк срок действия сессии.';

  @override
  String get authUsernameLabel => 'Имя пользователя';

  @override
  String get authPasswordLabel => 'Пароль';

  @override
  String authServerLine(String host) {
    return 'Сервер: $host';
  }

  @override
  String get authSubmittingLabel => 'Вход…';

  @override
  String authSignInWithWait(String wait) {
    return 'Войти · $wait';
  }

  @override
  String get authSignIn => 'Войти';

  @override
  String get authInvalidCredentials =>
      'Неверное имя пользователя или пароль. Попробуйте ещё раз.';

  @override
  String get authEmailNotVerified =>
      'Email этой учётной записи ещё не подтверждён — до подтверждения вход невозможен. Проверьте письмо с кодом.';

  @override
  String authRateLimited(String wait) {
    return 'Слишком много попыток входа. Следующая будет принята через $wait.';
  }

  @override
  String get authNetworkFailure =>
      'Не удалось связаться с сервером. Проверьте адрес сервера и подключение к сети.';

  @override
  String get authUnexpectedFailure =>
      'Не удалось войти — сервер ответил неожиданно. Попробуйте ещё раз, а если повторится — загляните в журнал сервера.';

  @override
  String get authForceBrandDescription =>
      'Пароль, заданный администратором, всегда временный. Пока он не сменён, остальные разделы приложения закрыты — доступны только смена пароля и выход.';

  @override
  String get authForceTitle => 'Смените пароль';

  @override
  String get authForceIntro =>
      'Ваш пароль задал администратор, поэтому он считается временным. Пока он не изменён, остальные разделы недоступны.';

  @override
  String get authForceSubmit => 'Сменить пароль и продолжить';

  @override
  String get authSignedIn => 'Вошли в систему';

  @override
  String authSignedInAs(String username) {
    return 'Вошли как $username';
  }

  @override
  String get authSignOut => 'Выйти';

  @override
  String get authChangedTitle => 'Пароль изменён';

  @override
  String get authChangedBody =>
      'Временный пароль больше не действует. Остальные разделы приложения снова доступны.';

  @override
  String get authChangedContinue => 'Перейти в приложение';

  @override
  String get authCurrentPasswordLabel => 'Текущий (временный) пароль';

  @override
  String get authNewPasswordLabel => 'Новый пароль';

  @override
  String get authRepeatPasswordLabel => 'Повторите новый пароль';

  @override
  String get authPasswordsMismatch => 'Пароли не совпадают';

  @override
  String get authChangeWrongCurrent =>
      'Текущий пароль неверен. Введите тот, который сообщил администратор.';

  @override
  String authChangeRateLimited(int seconds) {
    return 'Слишком много попыток. Попробуйте снова через $seconds с.';
  }

  @override
  String get authChangeNetwork => 'Сервер недоступен. Проверьте подключение.';

  @override
  String get authChangeUnexpected =>
      'Не удалось сменить пароль. Попробуйте ещё раз.';

  @override
  String get commonCancel => 'Отмена';

  @override
  String get appTitle => 'Structured Log';

  @override
  String monthShort(String month) {
    String _temp0 = intl.Intl.selectLogic(month, {
      '1': 'янв',
      '2': 'фев',
      '3': 'мар',
      '4': 'апр',
      '5': 'мая',
      '6': 'июн',
      '7': 'июл',
      '8': 'авг',
      '9': 'сен',
      '10': 'окт',
      '11': 'ноя',
      '12': 'дек',
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
  String get dashTitle => 'Дашборд';

  @override
  String get dashLoadFailed => 'Не удалось загрузить дашборд';

  @override
  String dashGreeting(String username) {
    return 'Здравствуйте, $username';
  }

  @override
  String get dashSubtitle =>
      'Администратор · быстрый доступ к тому, чем вы управляете и что можете просматривать';

  @override
  String get dashAllGroups => 'Все группы сервера';

  @override
  String get dashNoGroups => 'Групп пока нет';

  @override
  String get dashNoGroupsHint =>
      'Группы появятся здесь, как только кто-то их создаст.';

  @override
  String get dashProjects => 'Проекты';

  @override
  String get dashNoProjects => 'Проектов пока нет';

  @override
  String get dashNoProjectsHint =>
      'Проекты появятся здесь, как только кто-то заведёт их внутри группы.';

  @override
  String dashCreatedOn(String date) {
    return 'Создана $date';
  }

  @override
  String get dashOpen => 'Открыть';

  @override
  String get dashEntries => 'Записей';

  @override
  String get dashViewLogs => 'Смотреть логи';

  @override
  String get logsScopesLoadFailed => 'Не удалось загрузить список областей';

  @override
  String get logsFailureRetryRefresh => 'Попробуйте обновить страницу.';

  @override
  String get logsFailureForbidden => 'Нет доступа к этой области.';

  @override
  String get logsFailureNetwork => 'Сервер недоступен. Проверьте подключение.';

  @override
  String get logsFailureRetry => 'Попробуйте ещё раз.';

  @override
  String logsScopeProject(String name) {
    return 'Проект: $name';
  }

  @override
  String logsScopeGroup(String name) {
    return 'Группа: $name';
  }

  @override
  String get logsTitle => 'Логи';

  @override
  String get logsChangeScope => 'Изменить область';

  @override
  String get logsSearchPlaceholder => 'Поиск по событию';

  @override
  String get logsFilterCategory => 'Категория';

  @override
  String get logsFilterLogger => 'Logger';

  @override
  String get logsTimeFrom => 'С';

  @override
  String get logsTimeTo => 'По';

  @override
  String get logsTimeAny => 'любое';

  @override
  String get logsTimeAnyTime => 'Любое время';

  @override
  String get logsTimeApply => 'Применить';

  @override
  String get logsAddCorrelationId => '+ correlation id';

  @override
  String get logsSearch => 'Найти';

  @override
  String get logsReset => 'Сбросить';

  @override
  String get logsLivePaused => 'На паузе';

  @override
  String get logsLiveRealtime => 'В реальном времени';

  @override
  String get logsResume => 'Возобновить';

  @override
  String get logsPause => 'Пауза';

  @override
  String get logsLevelAny => 'Любой уровень';

  @override
  String get logsLevelTrace => 'Trace и выше';

  @override
  String get logsLevelDebug => 'Debug и выше';

  @override
  String get logsLevelInfo => 'Info и выше';

  @override
  String get logsLevelWarning => 'Warning и выше';

  @override
  String get logsLevelError => 'Error и выше';

  @override
  String get logsLevelCritical => 'Только critical';

  @override
  String get logsCorrelationDialogTitle => 'Фильтр по correlation id';

  @override
  String get logsCorrelationField => 'Поле';

  @override
  String get logsCorrelationValue => 'Значение';

  @override
  String get logsCorrelationNotNumber => 'Значение должно быть числом';

  @override
  String get logsCancel => 'Отмена';

  @override
  String get logsAdd => 'Добавить';

  @override
  String get logsEmptyNoResultsTitle => 'Ничего не найдено';

  @override
  String get logsEmptyNoEntriesTitle => 'Записей пока нет';

  @override
  String get logsEmptyNoResultsBody =>
      'Под текущие фильтры не подходит ни одна запись.';

  @override
  String get logsEmptyNoEntriesBody =>
      'Как только приложение пришлёт первую запись, она появится здесь.';

  @override
  String get logsLoadingOlder => 'Загружаются более ранние записи…';

  @override
  String get logsStalledTitle => 'Живая трансляция остановлена';

  @override
  String get logsStalledProjectBlocked =>
      'Проект заблокирован — новые записи по нему больше не приходят. Показанное ниже осталось от последней загрузки.';

  @override
  String logsStalledClosed(String reason) {
    return 'Сервер закрыл подписку ($reason). Список ниже остался от последней загрузки.';
  }

  @override
  String get logsReloadAndContinue => 'Перезагрузить и продолжить';

  @override
  String get logsLiveFeed =>
      'Лента в реальном времени — новые записи появляются снизу';

  @override
  String logsUnseen(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count новых записей',
      many: '$count новых записей',
      few: '$count новые записи',
      one: '$count новая запись',
    );
    return '$_temp0 · перейти к свежим';
  }

  @override
  String get logsPausedTooLong => 'Пауза длилась слишком долго';

  @override
  String get logsPausedOverflowBody =>
      'Часть событий не поместилась в буфер. Возобновление перезагрузит свежую страницу целиком, а не покажет неполный список.';

  @override
  String logsPausedBuffered(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count записи',
      many: '$count записей',
      few: '$count записи',
      one: '$count запись',
    );
    return 'Лента на паузе · накоплено $_temp0';
  }

  @override
  String get logsBackToFeed => 'К ленте';

  @override
  String get logsSelectEntryTitle => 'Выберите запись';

  @override
  String get logsSelectEntryBody =>
      'Слева — лента; здесь будет запись целиком, вместе с произвольными полями, которые прислало приложение.';

  @override
  String get logsNoScopesTitle => 'Нет доступных областей';

  @override
  String get logsNoScopesBody =>
      'Логи видны в проектах и группах, на которые у вас есть роль. Попросите администратора выдать доступ.';

  @override
  String get logsPickScopeTitle => 'Выберите область';

  @override
  String get logsPickScopeBody =>
      'Логи запрашиваются по одному проекту или одной группе — без объединения нескольких.';

  @override
  String get logsProjects => 'Проекты';

  @override
  String get logsGroups => 'Группы';

  @override
  String get logsBlocked => 'заблокирован';

  @override
  String get logsCopy => 'Копировать';

  @override
  String get logsStandardFields => 'СТАНДАРТНЫЕ ПОЛЯ';

  @override
  String get logsContext => 'КОНТЕКСТ';

  @override
  String get resCancel => 'Отмена';

  @override
  String get resOpen => 'Открыть';

  @override
  String get resRevoke => 'Отозвать';

  @override
  String get resClose => 'Закрыть';

  @override
  String get resAdd => 'Добавить';

  @override
  String get resDelete => 'Удалить';

  @override
  String get resSave => 'Сохранить';

  @override
  String get resGroup => 'Группа';

  @override
  String get resBlocked => 'Заблокирован';

  @override
  String get resActive => 'Активен';

  @override
  String resGroupPrefix(String name) {
    return 'Группа: $name';
  }

  @override
  String resProjectPrefix(String name) {
    return 'Проект: $name';
  }

  @override
  String get resFailForbidden =>
      'Недостаточно прав. Это действие доступно администратору, а для проектов внутри группы — ещё и её владельцу.';

  @override
  String get resFailConflict => 'Такое имя уже занято. Выберите другое.';

  @override
  String get resFailInvalid => 'Проверьте заполненные поля.';

  @override
  String get resFailNotFound => 'Объект не найден — возможно, он уже удалён.';

  @override
  String get resFailUnauthorized => 'Сессия истекла. Войдите заново.';

  @override
  String resFailRateLimited(int seconds) {
    return 'Слишком много попыток. Попробуйте через $seconds с.';
  }

  @override
  String get resFailNetwork => 'Сервер недоступен. Проверьте подключение.';

  @override
  String resFailServer(int status) {
    return 'Сервер ответил ошибкой ($status). Попробуйте ещё раз.';
  }

  @override
  String resBytesMb(String count) {
    return '$count МБ';
  }

  @override
  String resBytesKb(String count) {
    return '$count КБ';
  }

  @override
  String resDaysCount(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days дня',
      many: '$days дней',
      few: '$days дня',
      one: '$days день',
    );
    return '$_temp0';
  }

  @override
  String resSubjectTeam(int id) {
    return 'Команда #$id';
  }

  @override
  String resSubjectUser(int id) {
    return 'Пользователь #$id';
  }

  @override
  String resSubjectTeamGen(int id) {
    return 'команды #$id';
  }

  @override
  String resSubjectUserGen(int id) {
    return 'пользователя #$id';
  }

  @override
  String get resNoLimit => 'без лимита';

  @override
  String get resFieldRetention => 'Срок хранения, дней (retention_days)';

  @override
  String get resFieldMaxEntries => 'Лимит записей (max_entries)';

  @override
  String get resFieldMaxBytes => 'Лимит объёма, МБ (max_bytes)';

  @override
  String get resNewProject => 'Новый проект';

  @override
  String get resProjectNameLabel => 'Название проекта';

  @override
  String get resNewProjectNote =>
      'Секретный ключ для приёма логов создаётся отдельно, на экране проекта, после его создания.';

  @override
  String get resCreateProject => 'Создать проект';

  @override
  String get resEditQuota => 'Изменить квоту';

  @override
  String get resKeyCreated => 'Ключ создан';

  @override
  String resKeyRevealSubtitle(String project, String label) {
    return 'Проект $project · метка «$label»';
  }

  @override
  String get resKeyRevealWarning =>
      'Значение показывается только один раз. После закрытия окна оно нигде не будет доступно — сохраните его сейчас.';

  @override
  String get resKeySavedClose => 'Я сохранил(а) ключ — закрыть';

  @override
  String get resGrantAccess => 'Предоставить доступ';

  @override
  String get resGrant => 'Предоставить';

  @override
  String get resRecipient => 'Получатель';

  @override
  String get resUser => 'Пользователь';

  @override
  String get resTeam => 'Команда';

  @override
  String get resRecipientName => 'Имя получателя';

  @override
  String get resSearchUserHint => 'Начните вводить имя пользователя…';

  @override
  String get resSearchTeamHint => 'Начните вводить название команды…';

  @override
  String get resRole => 'Роль';

  @override
  String resTeamMembersTitle(String team) {
    return 'Состав команды «$team»';
  }

  @override
  String get resAddMember => 'Добавить участника';

  @override
  String get resNoMembers => 'Участников пока нет';

  @override
  String get resNoMembersHint => 'Добавьте первого через поиск выше.';

  @override
  String get resGroups => 'Группы';

  @override
  String get resCreateGroup => 'Создать группу';

  @override
  String get resGroupsLoadFailed => 'Не удалось загрузить группы';

  @override
  String get resNoGroups => 'Групп пока нет';

  @override
  String get resNoGroupsHint =>
      'Группа владеет проектами. Создайте первую, чтобы завести в ней проект и начать принимать логи.';

  @override
  String resCreatedOn(String date) {
    return 'Создана $date';
  }

  @override
  String resKeyCreatedOn(String date) {
    return 'Создан $date';
  }

  @override
  String resKeyRevokedOn(String date) {
    return 'Отозван $date';
  }

  @override
  String get resNewGroup => 'Новая группа';

  @override
  String get resGroupNameLabel => 'Название группы';

  @override
  String get resNewGroupNote =>
      'После создания группа не имеет владельца — выдайте роль owner нужному пользователю или команде на экране группы.';

  @override
  String get resTeams => 'Команды';

  @override
  String get resNoTeams => 'Команд пока нет';

  @override
  String get resNoTeamsHint =>
      'Команда позволяет выдать роль сразу нескольким пользователям — всем её текущим участникам.';

  @override
  String get resMembers => 'Состав';

  @override
  String get resNewTeam => 'Новая команда';

  @override
  String get resTeamNameLabel => 'Название команды';

  @override
  String get resCreateTeam => 'Создать команду';

  @override
  String get resNewTeamNote =>
      'После создания команда пуста — добавьте участников на экране «Состав команды».';

  @override
  String get resProjectShort => 'Проект';

  @override
  String get resProjects => 'Проекты';

  @override
  String get resProjectsLoadFailed => 'Не удалось загрузить проекты';

  @override
  String get resNoProjects => 'Проектов пока нет';

  @override
  String get resNoProjectsHint =>
      'Создайте первый — он будет принимать логи по секретному ключу.';

  @override
  String get resQuotaNoEntryLimit => 'без лимита записей';

  @override
  String resQuotaEntryLimit(String count) {
    return 'лимит $count записей';
  }

  @override
  String resQuotaLine(String entries, String days) {
    return '$entries · retention $days';
  }

  @override
  String get resAccess => 'Доступ';

  @override
  String get resNoAccess => 'Доступа пока никому не выдано';

  @override
  String get resNoAccessGroupHint =>
      'Предоставьте роль owner или user, чтобы открыть доступ к этой группе и её проектам.';

  @override
  String get resNoAccessProjectHint =>
      'Предоставьте роль owner или user, чтобы открыть доступ к этому проекту.';

  @override
  String resRevokeAccessTitle(String subject) {
    return 'Отозвать доступ у «$subject»?';
  }

  @override
  String resRevokeRoleGroup(String role) {
    return 'Роль «$role» на эту группу будет отозвана немедленно.';
  }

  @override
  String resRevokeRoleProject(String role) {
    return 'Роль «$role» на этот проект будет отозвана немедленно.';
  }

  @override
  String get resProjectLoadFailed => 'Не удалось загрузить проект';

  @override
  String get resTryAgain => 'Попробуйте ещё раз.';

  @override
  String get resProjectBlockedBanner =>
      'Проект заблокирован администратором: приём новых логов и запрос уже сохранённых логов этого проекта отключены до разблокировки. Секретные ключи проекта не отозваны.';

  @override
  String get resBlock => 'Заблокировать';

  @override
  String get resUnblock => 'Разблокировать';

  @override
  String get resOpenLogs => 'Открыть логи';

  @override
  String resBlockTitle(String name) {
    return 'Заблокировать проект «$name»?';
  }

  @override
  String get resBlockMessage =>
      'Приём новых логов и запрос уже сохранённых логов этого проекта будут отключены до разблокировки. Секретные ключи проекта не отзываются.';

  @override
  String get resQuotaAndUsage => 'Квота и использование';

  @override
  String get resRetentionRow => 'Срок хранения (retention_days)';

  @override
  String get resEntriesBar => 'Записей (max_entries)';

  @override
  String get resSizeBar => 'Объём (max_bytes)';

  @override
  String get resSecretKeys => 'Секретные ключи проекта';

  @override
  String get resCreateKey => 'Создать ключ';

  @override
  String get resNoKeys => 'Секретных ключей пока нет';

  @override
  String get resNoKeysHint =>
      'Создайте первый, чтобы приложение могло присылать логи.';

  @override
  String get resNewKey => 'Новый секретный ключ';

  @override
  String get resKeyLabelField => 'Метка';

  @override
  String get resNewKeyNote =>
      'Метка нужна, чтобы потом понять, какое приложение им пользуется. Значение ключа будет показано один раз.';

  @override
  String resRevokeKeyTitle(String label) {
    return 'Отозвать ключ «$label»?';
  }

  @override
  String get resRevokeKeyMessage =>
      'Приложения, которые присылают логи с этим ключом, сразу получат отказ. Отзыв необратим — при необходимости создайте новый ключ.';

  @override
  String get shellNavOverview => 'Обзор';

  @override
  String get shellNavDashboard => 'Дашборд';

  @override
  String get shellNavAdministration => 'Администрирование';

  @override
  String get shellNavGroups => 'Группы';

  @override
  String get shellNavUsers => 'Пользователи';

  @override
  String get shellNavAudit => 'Аудит';

  @override
  String get shellNavLogs => 'Логи';

  @override
  String get shellNavLogSearch => 'Поиск логов';

  @override
  String get shellAccountFallback => 'Аккаунт';

  @override
  String get shellRoleAdmin => 'Администратор';

  @override
  String get shellRoleUser => 'Пользователь';

  @override
  String get shellAccountSettings => 'Настройки аккаунта';

  @override
  String get shellSignOut => 'Выйти';

  @override
  String get shellDeleteInvalidPassword => 'Текущий пароль неверен.';

  @override
  String get shellDeletePrimaryAdmin =>
      'Основного администратора удалить нельзя — эта учётная запись защищена навсегда.';

  @override
  String shellRateLimited(int seconds) {
    return 'Слишком много попыток. Попробуйте снова через $seconds с.';
  }

  @override
  String get shellNetworkFailure => 'Сервер недоступен. Проверьте подключение.';

  @override
  String get shellDeleteFailed =>
      'Не удалось удалить аккаунт. Попробуйте ещё раз.';

  @override
  String get shellDeleteTitle => 'Удалить аккаунт?';

  @override
  String get shellDeleteMessage =>
      'Это необратимо. Ваша учётная запись будет заблокирована навсегда, все текущие сессии завершены немедленно. Имя пользователя останется зарезервированным.';

  @override
  String get shellDeleteConfirm => 'Удалить аккаунт';

  @override
  String get shellDeletePasswordLabel => 'Подтвердите текущим паролем';

  @override
  String get shellSettingsTitle => 'Настройки аккаунта';

  @override
  String get shellSectionProfile => 'Профиль';

  @override
  String get shellUsername => 'Имя пользователя';

  @override
  String get shellEmail => 'Email';

  @override
  String get shellDisplayName => 'Отображаемое имя';

  @override
  String get shellSectionSecurity => 'Безопасность';

  @override
  String get shellPasswordChanged =>
      'Пароль изменён. Сессия не прервана — можно продолжать работу.';

  @override
  String get shellPasswordHintForm =>
      'Потребуется текущий пароль. Смена не завершает вашу сессию — вы останетесь в приложении.';

  @override
  String get shellChangePassword => 'Сменить пароль';

  @override
  String get shellPasswordHintRow =>
      'Потребуется текущий пароль. Смена не завершает вашу сессию.';

  @override
  String get shellSectionDanger => 'Опасная зона';

  @override
  String get shellDeleteAccountTitle => 'Удалить аккаунт';

  @override
  String get shellDeleteAccountText =>
      'Безвозвратно удаляет вашу учётную запись. Все ваши сессии будут завершены немедленно. Действие нельзя отменить.';

  @override
  String get shellSectionLanguage => 'Язык';

  @override
  String get shellLanguageHint =>
      'Язык интерфейса. Пока вы не выбрали, используется язык браузера.';

  @override
  String get shellLanguageSystem => 'Как в браузере';

  @override
  String get shellLanguageEnglish => 'English';

  @override
  String get shellLanguageRussian => 'Русский';

  @override
  String get usersFailureCannotDeletePrimaryAdmin =>
      'Основного администратора удалить нельзя — эта учётная запись защищена навсегда, независимо от того, сколько других администраторов есть в системе.';

  @override
  String get usersFailureForbidden =>
      'Недостаточно прав. Это действие доступно только администратору.';

  @override
  String get usersFailureUsernameTaken =>
      'Такое имя пользователя уже занято. Выберите другое.';

  @override
  String get usersFailureDeletedAccount =>
      'Учётная запись удалена — разблокировать её нельзя. Удаление необратимо.';

  @override
  String get usersFailureSoleGroupOwner =>
      'Пользователь — единственный владелец одной или нескольких групп. Сначала назначьте другого владельца.';

  @override
  String get usersFailureConflict =>
      'Конфликт при сохранении. Попробуйте ещё раз.';

  @override
  String get usersFailureSelfDeletion =>
      'Нельзя удалить самого себя этим способом.';

  @override
  String get usersFailureInvalidRequest => 'Проверьте заполненные поля.';

  @override
  String get usersFailureNotFound =>
      'Пользователь не найден — возможно, уже удалён кем-то другим.';

  @override
  String get usersFailureUnauthorized => 'Сессия истекла. Войдите заново.';

  @override
  String usersFailureRateLimited(int seconds) {
    return 'Слишком много попыток. Попробуйте через $seconds с.';
  }

  @override
  String get usersFailureNetwork => 'Сервер недоступен. Проверьте подключение.';

  @override
  String usersFailureServer(int statusCode) {
    return 'Сервер ответил ошибкой ($statusCode). Попробуйте ещё раз.';
  }

  @override
  String get usersPageTitle => 'Пользователи';

  @override
  String get usersCreateUser => 'Создать пользователя';

  @override
  String get usersLoadFailedTitle => 'Не удалось загрузить пользователей';

  @override
  String get usersEmptyTitle => 'Пользователей пока нет';

  @override
  String get usersEmptyDescription =>
      'Здесь появятся учётные записи, как только вы создадите первую.';

  @override
  String get usersShowMore => 'Показать ещё';

  @override
  String usersCreatedOn(String date) {
    return 'Создан $date';
  }

  @override
  String get usersStatusDeleted => 'Удалён';

  @override
  String get usersStatusBlocked => 'Заблокирован';

  @override
  String get usersStatusActive => 'Активен';

  @override
  String get usersPrimaryAdmin => 'Основной администратор';

  @override
  String get usersTemporaryPassword => 'Временный пароль';

  @override
  String get usersOpen => 'Открыть';

  @override
  String get usersUnblock => 'Разблокировать';

  @override
  String get usersBlock => 'Заблокировать';

  @override
  String get usersDelete => 'Удалить';

  @override
  String get usersCancel => 'Отмена';

  @override
  String get usersEditBreadcrumb => 'Изменить';

  @override
  String get usersEditTitle => 'Изменить учётную запись';

  @override
  String get usersEditSubtitle =>
      'Доступно только администратору. Имя пользователя и роли этим экраном не меняются.';

  @override
  String get usersFieldUsername => 'Имя пользователя';

  @override
  String get usersFieldEmail => 'Email';

  @override
  String get usersFieldDisplayName => 'Отображаемое имя';

  @override
  String get usersNewPasswordLabel => 'Новый пароль (необязательно)';

  @override
  String get usersNewPasswordHint =>
      'Немедленно завершит текущую сессию пользователя — при следующем входе потребуется сменить этот пароль на свой.';

  @override
  String get usersFieldPassword => 'Пароль';

  @override
  String get usersKeepPassword => 'Не менять';

  @override
  String get usersSaveChanges => 'Сохранить изменения';

  @override
  String get usersCreateDialogTitle => 'Новый пользователь';

  @override
  String get usersFieldTemporaryPassword => 'Временный пароль';

  @override
  String get usersFieldDisplayNameOptional =>
      'Отображаемое имя (необязательно)';

  @override
  String get usersTemporaryPasswordHint =>
      'Пользователю нужно будет сменить этот пароль при первом входе.';

  @override
  String usersBlockConfirmTitle(String username) {
    return 'Заблокировать «$username»?';
  }

  @override
  String get usersBlockConfirmMessage =>
      'Текущая сессия пользователя завершится немедленно. Вход станет невозможен до разблокировки.';

  @override
  String usersDeleteConfirmTitle(String username) {
    return 'Удалить «$username»?';
  }

  @override
  String get usersDeleteConfirmMessage =>
      'Необратимо: учётная запись перестанет существовать, все её сессии будут завершены немедленно. Пароль не запрашивается — это ваше административное действие. Отменить удаление нельзя — при необходимости придётся создать новую учётную запись.';

  @override
  String get usersSoleOwnerTitle => 'Сначала передайте владение';

  @override
  String get usersSoleOwnerDescription =>
      'Пользователь — единственный владелец (owner) следующих групп. Выдайте роль владельца ещё кому-то в каждой из них, прежде чем удаление станет возможным.';

  @override
  String get usersSoleOwnerTag => 'единственный owner';

  @override
  String get usersGrantRole => 'Выдать роль';

  @override
  String get usersGotIt => 'Понятно';

  @override
  String usersScopeGroupLabel(String name) {
    return 'группа: $name';
  }

  @override
  String get usersPrimaryAdminBanner =>
      'Это основная учётная запись администратора. Удалить её нельзя — ни другому администратору, ни ей самой; сервер отклонит такой запрос с кодом cannot_delete_primary_admin.';

  @override
  String get usersProfileTitle => 'Профиль';

  @override
  String get usersFieldCreated => 'Создан';

  @override
  String get usersSecurityTitle => 'Безопасность';

  @override
  String get usersPasswordTemporary =>
      'Временный — потребует смены при следующем входе';

  @override
  String get usersPasswordSetByUser => 'Задан самим пользователем';

  @override
  String get usersRolesTitle => 'Роли';

  @override
  String get usersNoRoles => 'Ролей пока не выдано.';

  @override
  String get usersRevoke => 'Отозвать';

  @override
  String usersRevokeConfirmTitle(String role) {
    return 'Отозвать роль «$role»?';
  }

  @override
  String usersRevokeConfirmMessage(String scope) {
    return 'Доступ ($scope) будет отозван немедленно.';
  }

  @override
  String get usersScopeGlobal => 'вся система';

  @override
  String usersScopeProjectLabel(String name) {
    return 'проект: $name';
  }

  @override
  String get usersScopeTypeGroup => 'Группа';

  @override
  String get usersScopeTypeProject => 'Проект';

  @override
  String get usersScopePickerPlaceholder => 'Начните вводить название…';

  @override
  String get usersRecentAuditTitle => 'Последние события аудита';

  @override
  String get usersNoAuditEvents => 'Событий пока нет.';

  @override
  String get usersOpenInAudit =>
      'Открыть в аудите с фильтром по этому пользователю';
}
