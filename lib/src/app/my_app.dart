import 'package:cosmic_fury/src/pages/intro/intro_page.dart';
import 'package:flutter/material.dart';

class MyApp extends StatelessWidget {
const MyApp({ Key? key }) : super(key: key);

  @override
  Widget build(BuildContext context){
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: IntroPage(),
    );
  }
}