import 'package:dio/dio.dart';

/// Nothing to replace off the web.
///
/// `dart:io`'s adapter already hands back the body as it arrives, which is
/// what `ResponseType.stream` means and what the live log subscription needs.
/// Returning `null` leaves dio on its own default — including in tests, which
/// run on the VM and inject their own adapter anyway.
HttpClientAdapter? createStreamingAdapter() => null;
