import 'package:cosmic_fury/src/pages/intro/intro_page.dart';
import 'package:flutter/material.dart';
import 'package:responsive_sizer/responsive_sizer.dart';

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ResponsiveSizer(
      builder: (context, orientation, screenType) {
        return MaterialApp(
          home: const IntroPage(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}