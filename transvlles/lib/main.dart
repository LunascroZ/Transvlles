import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:transvlles/screens/afficher_ligne.dart'; 
import 'package:transvlles/screens/hub_page.dart';

/// Point d'entrée principal de l'application.
/// 
/// Fonction asynchrone requise pour garantir l'initialisation des composants 
/// natifs (WidgetsBinding) et la connexion aux services cloud (Firebase) 
/// avant le rendu du premier widget de l'arborescence.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); 
  runApp(const MyApp());
}

/// Racine de l'arbre des widgets de l'application.
/// 
/// Gère la configuration globale de l'interface utilisateur, incluant 
/// le routage de base et l'application stricte de la charte graphique (Thème sombre).
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Transvlles',
      debugShowCheckedModeBanner: false, 
      
      // Définition de la charte graphique globale (Dark Mode + Accents roses)
      theme: ThemeData(
        brightness: Brightness.dark, 
        scaffoldBackgroundColor: Colors.grey[850],
        
        // Personnalisation de la barre de navigation supérieure
        appBarTheme: const AppBarTheme(
          backgroundColor: Color.fromARGB(255, 0, 0, 0),
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.pink, 
            fontWeight: FontWeight.bold, 
            fontSize: 20,
          ),
        ),
        
        // Standardisation de l'apparence des boutons d'action
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.pink, 
            foregroundColor: Colors.white,
          ),
        ),
      ),

      // Définition de l'écran d'accueil par défaut
      home: const HubPage(), 

      // Table de routage statique pour la navigation intra-application
      routes: {
        '/lignes': (context) => const AfficherLigne(),
      },
    );
  }
}