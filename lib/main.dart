import 'package:cosmic_fury/src/app/my_app.dart';
import 'package:flutter/widgets.dart';
import 'package:responsive_sizer/responsive_sizer.dart';

void main() {
  runApp(
    ResponsiveSizer(
      builder: (context, orientation, deviceType) {
        return const MyApp();
      },
    ),
  );
}