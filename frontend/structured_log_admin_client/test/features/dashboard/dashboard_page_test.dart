import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:structured_log_admin_client/features/dashboard/presentation/dashboard_cubit.dart';
import 'package:structured_log_admin_client/features/dashboard/presentation/dashboard_page.dart';
import 'package:structured_log_admin_client/features/resources/application/manage_resources.dart';
import 'package:structured_log_admin_client/features/resources/domain/resources_repository.dart';
import 'package:structured_log_admin_client/shared/api/api_failure.dart';
import 'package:structured_log_admin_client/shared/api/dto/resource_dto.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

/// `ManageGroups.list`/`ManageProjects.search`/`.get` is all
/// [DashboardCubit] calls — everything else throws if the test does not set
/// it up, the same convention `_FakeRoleAssignments` in
/// `resources_screens_test.dart` uses.
class _FakeRepository implements ResourcesRepository {
  var groupList = <GroupDto>[];
  var projectList = <ProjectDto>[];

  /// Keyed by id, what [project] answers — a project search result carries
  /// no usage, only this does, same as the real server.
  var projectDetail = <int, ProjectDto>{};

  ApiFailure? groupsFailure;

  @override
  Future<Either<ApiFailure, List<GroupDto>>> groups({String? name}) async {
    if (groupsFailure != null) return left(groupsFailure!);
    return right(groupList);
  }

  @override
  Future<Either<ApiFailure, List<ProjectDto>>> searchProjects({
    String? name,
  }) async => right(projectList);

  @override
  Future<Either<ApiFailure, ProjectDto>> project(int projectId) async {
    final detail = projectDetail[projectId];
    return detail == null
        ? left(const ApiFailure.notFound(code: 'not_found'))
        : right(detail);
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} is not used by dashboard_page_test.dart',
  );
}

Widget _host(Widget child) => FluentApp(
  theme: AdminTheme.light(),
  home: ScaffoldPage(padding: EdgeInsets.zero, content: child),
);

GroupDto _group(int id, String name) =>
    GroupDto(id: id, name: name, createdAt: DateTime.utc(2026, 2, 14));

ProjectDto _project(
  int id,
  int groupId,
  String name, {
  int? entryCount,
  int? maxEntries,
}) => ProjectDto(
  id: id,
  groupId: groupId,
  name: name,
  retentionDays: 30,
  maxEntries: maxEntries,
  isBlocked: false,
  createdAt: DateTime.utc(2026, 2, 14),
  entryCount: entryCount,
);

void main() {
  late _FakeRepository repository;

  setUp(() {
    repository = _FakeRepository();
  });

  Future<DashboardCubit> pump(
    WidgetTester tester, {
    void Function(int, String)? onOpenGroup,
    void Function(int, String)? onOpenLogs,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = DashboardCubit(
      ManageGroups(repository),
      ManageProjects(repository),
    )..load();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      _host(
        BlocProvider.value(
          value: cubit,
          child: DashboardPage(
            username: 'alex',
            onOpenGroup: onOpenGroup ?? (_, _) {},
            onOpenLogs: onOpenLogs ?? (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  testWidgets('no groups and no projects invites rather than errors', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Групп пока нет'), findsOneWidget);
    expect(find.text('Проектов пока нет'), findsOneWidget);
  });

  testWidgets('a group card shows its name, the admin badge and usage', (
    tester,
  ) async {
    repository.groupList = [_group(1, 'Acme Corp')];
    repository.projectList = [
      _project(1, 1, 'payments-api', entryCount: 842, maxEntries: 1000),
    ];
    repository.projectDetail = {
      1: _project(1, 1, 'payments-api', entryCount: 842, maxEntries: 1000),
    };

    await pump(tester);

    expect(find.text('Здравствуйте, alex'), findsOneWidget);
    expect(find.text('admin'), findsOneWidget);
    expect(find.text('payments-api'), findsOneWidget);
    expect(
      find.text('Acme Corp'),
      findsNWidgets(2),
      reason:
          'the group card\'s own name, and the project card\'s group '
          'label — resolved from the loaded group list rather than a '
          'second request',
    );
    expect(find.textContaining('842'), findsOneWidget);
  });

  testWidgets('opening a group card reports that group\'s id and name', (
    tester,
  ) async {
    repository.groupList = [_group(7, 'Globex Retail')];
    ({int id, String name})? opened;

    await pump(
      tester,
      onOpenGroup: (id, name) => opened = (id: id, name: name),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();

    expect(opened, (id: 7, name: 'Globex Retail'));
  });

  testWidgets('opening a project card\'s logs reports that project', (
    tester,
  ) async {
    repository.groupList = [_group(1, 'Acme Corp')];
    repository.projectList = [_project(3, 1, 'notification-svc')];
    repository.projectDetail = {3: _project(3, 1, 'notification-svc')};
    ({int id, String name})? opened;

    await pump(tester, onOpenLogs: (id, name) => opened = (id: id, name: name));
    await tester.tap(find.text('Смотреть логи'));
    await tester.pumpAndSettle();

    expect(opened, (id: 3, name: 'notification-svc'));
  });

  testWidgets('a refused group list is explained, not left blank', (
    tester,
  ) async {
    repository.groupsFailure = const ApiFailure.forbidden(code: 'forbidden');

    await pump(tester);

    expect(find.text('Не удалось загрузить дашборд'), findsOneWidget);
  });

  testWidgets('a project whose own detail request fails still shows, '
      'without usage', (tester) async {
    repository.groupList = [_group(1, 'Acme Corp')];
    repository.projectList = [_project(9, 1, 'mobile-ios')];
    // No entry in projectDetail — `project(9)` answers notFound, and the
    // card falls back to the list version of the project.

    await pump(tester);

    expect(find.text('mobile-ios'), findsOneWidget);
  });
}
