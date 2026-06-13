import 'package:flutter/material.dart';
import 'package:transvlles/screens/afficher_ligne.dart';
import 'package:transvlles/screens/homepage.dart';

/// Écran d'accueil principal de l'application (Hub).
/// 
/// Interface modernisée servant de point d'entrée pour diriger l'utilisateur 
/// vers les modules Transports ou Ville.
class HubPage extends StatelessWidget {
  const HubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // Fond sombre profond plus élégant que le gris de base
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- EN-TÊTE IMMERSIF (Hero Header) ---
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 30, // S'adapte à l'encoche de l'iPhone
                left: 24, 
                right: 24, 
                bottom: 40
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFE91E63), Color(0xFF121212)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 1.0],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(color: Colors.pink.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))
                          ]
                        ),
                        child: const Icon(Icons.hub, color: Colors.pink, size: 28),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'Transvles',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    "Bonjour,",
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w300, color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Que souhaitez-vous explorer ?",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
            ),
            
            // --- SECTION DES CARTES DE NAVIGATION ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  _buildModernCard(
                    context: context,
                    title: "Transports en commun",
                    subtitle: "Horaires, itinéraires, retards et alertes en temps réel.",
                    icon: Icons.directions_transit,
                    gradientColors: [Colors.pinkAccent, Colors.deepPurpleAccent],
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const AfficherLigne()));
                    },
                  ),
                  
                  const SizedBox(height: 24),
                  
                  _buildModernCard(
                    context: context,
                    title: "Ma Ville",
                    subtitle: "Cartographie, espaces verts et signalements citoyens.",
                    icon: Icons.eco,
                    gradientColors: [Colors.teal, Colors.green],
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const MapPage()));
                    },
                  ),
                  const SizedBox(height: 40), // Marge en bas pour respirer
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Construit une carte de navigation moderne avec fond dégradé et icône en filigrane.
  Widget _buildModernCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // 1. ON AUGMENTE LA HAUTEUR DE 160 À 190 POUR LAISSER RESPIRER LE TEXTE
        height: 190, 
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: gradientColors[0].withValues(alpha: 0.4),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Icône géante semi-transparente en arrière-plan
            Positioned(
              right: -20,
              bottom: -20,
              child: Icon(
                icon,
                size: 140,
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            
            // Contenu de la carte
            Padding(
              // 2. ON RÉDUIT LÉGÈREMENT LES MARGES DE 24 À 20
              padding: const EdgeInsets.all(20.0), 
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: Colors.white, size: 28),
                  ),
                  const Spacer(),
                  Text(
                    title,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.9)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis, // Coupe le texte avec "..." s'il est vraiment trop long
                  ),
                ],
              ),
            ),
            
            // Petite flèche indicative en haut à droite
            Positioned(
              right: 20,
              top: 20,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}