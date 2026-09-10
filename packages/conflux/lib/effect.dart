/// Lazy, typed effects and their execution runtime.
library;

import 'dart:async';

import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:context/context.dart';

part 'src/effect/builder.dart';
part 'src/effect/cause.dart';
part 'src/effect/clock.dart';
part 'src/effect/effect.dart';
part 'src/effect/execution.dart';
part 'src/effect/exit.dart';
part 'src/effect/runtime.dart';
