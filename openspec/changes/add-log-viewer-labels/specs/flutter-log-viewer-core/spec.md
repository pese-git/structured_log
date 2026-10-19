## ADDED Requirements

### Requirement: LogViewerLabels — общий для скинов набор подписей просмотрщика
`structured_log_flutter` SHALL экспортировать неизменяемый класс `LogViewerLabels` с `const`-конструктором, в
котором каждое поле необязательно (`null` по умолчанию): `searchHint`, `pause`, `resume`, `clear`,
`levelFilterLabel` (функция `String Function(LogLevel? minLevel)`, `null`-аргумент — «все уровни»),
`allCategories`, `pageTitle`, `emptyTitle`, `emptyMessage`, `noMatchesTitle`, `noMatchesMessage`,
`clearFilters`, `contextHeading`, `copyContext`, `close`, `backToList`. Поле со значением `null` SHALL означать «подпись скина по
умолчанию». Класс SHALL предоставлять `copyWith`. Класс SHALL NOT содержать встроенных переводов и SHALL NOT
импортировать ни одну дизайн-систему (Material/Cupertino/Fluent) и `flutter_localizations`.

#### Scenario: Пустой набор не задаёт ни одной подписи
- **WHEN** создаётся `const LogViewerLabels()`
- **THEN** все его поля равны `null`

#### Scenario: copyWith меняет только указанное поле
- **WHEN** у набора с заданными `searchHint` и `pause` вызывается `copyWith(pause: 'Стоп')`
- **THEN** результат имеет `pause == 'Стоп'` и прежний `searchHint`, а исходный набор не изменён

#### Scenario: Набор доступен из барреля ядра
- **WHEN** код импортирует только `package:structured_log_flutter/structured_log_flutter.dart`
- **THEN** тип `LogViewerLabels` доступен

### Requirement: Необязательный делегат локализации с английским и русским
`structured_log_flutter` SHALL экспортировать `LogViewerLocalizations` со свойством `labels` типа
`LogViewerLabels`, статическим `delegate` (`LocalizationsDelegate<LogViewerLocalizations>`) и статическим
`of(BuildContext)`, возвращающим `null`, если делегат не зарегистрирован. Делегат SHALL поддерживать языки `en` и
`ru` (по `languageCode`) и SHALL загружаться синхронно. Для `en` `labels` SHALL быть пустым набором (все поля
`null`), для `ru` — набором, в котором задано каждое поле. Пакет SHALL NOT зависеть от `flutter_localizations` и
`intl`.

`LogViewerLocalizations.resolve(BuildContext, LogViewerLabels)` SHALL возвращать набор, в котором каждое поле
берётся из переданного набора, если оно не `null`, иначе из `labels` зарегистрированного делегата, иначе
остаётся `null`.

#### Scenario: Русский набор задаёт все подписи
- **WHEN** делегат загружается для `Locale('ru')`
- **THEN** у `labels` результата не `null` ни одно поле, и `levelFilterLabel(null)` возвращает `Все`

#### Scenario: Английский набор оставляет подписи скинам
- **WHEN** делегат загружается для `Locale('en')`
- **THEN** у `labels` результата все поля `null`

#### Scenario: Неподдерживаемый язык
- **WHEN** у делегата спрашивают `isSupported(Locale('de'))`
- **THEN** ответ `false`

#### Scenario: Явная подпись важнее делегата
- **WHEN** делегат `ru` зарегистрирован и `resolve` вызывается с набором, где задан только `pause: 'Стоп'`
- **THEN** у результата `pause == 'Стоп'`, а остальные поля — из русского набора делегата

#### Scenario: Без делегата resolve возвращает переданный набор
- **WHEN** делегат не зарегистрирован и `resolve` вызывается с набором, где задан только `pause`
- **THEN** у результата задан только `pause`
