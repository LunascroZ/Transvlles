import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:transvlles/screens/afficher_ligne.dart'; 
// Dans main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); 
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Transvlles',
      debugShowCheckedModeBanner: false, 
      
      theme: ThemeData(
        brightness: Brightness.dark, 
        scaffoldBackgroundColor: Colors.grey[850],
        appBarTheme: const AppBarTheme(
          backgroundColor: Color.fromARGB(255, 0, 0, 0),
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.pink, 
            fontWeight: FontWeight.bold, 
            fontSize: 20
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.pink, 
            foregroundColor: Colors.white
          ),
        ),
      ),

      home:  AfficherLigne(), 

      routes: {

        '/lignes': (context) =>  AfficherLigne(),
      },
    );
  }
}