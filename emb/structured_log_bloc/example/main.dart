import 'package:bloc/bloc.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_bloc/structured_log_bloc.dart';

sealed class CounterEvent {}

class Incremented extends CounterEvent {
  @override
  String toString() => 'Incremented()';
}

class CounterBloc extends Bloc<CounterEvent, int> {
  CounterBloc() : super(0) {
    on<Incremented>((event, emit) => emit(state + 1));
  }
}

class ThemeCubit extends Cubit<String> {
  ThemeCubit() : super('light');

  void toggle() => emit(state == 'light' ? 'dark' : 'light');
}

Future<void> main() async {
  StructlogConfiguration.configure(
    sinks: [LogSink(name: 'console', output: coloredConsoleOutput)],
  );
  Bloc.observer = StructuredLogBlocObserver();

  final counter = CounterBloc()..add(Incremented());
  final theme = ThemeCubit()..toggle();

  await counter.stream.first;
  await counter.close();
  await theme.close();
}
