import 'package:bkdash_sanitary_ware/app/app.dart';
import 'package:bkdash_sanitary_ware/app/app_dependencies.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = await AppDependencies.create();
  runApp(BkdashApp(dependencies: dependencies));
}
