import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // Requis pour l'utilisation de debugPrint

/// Service de gestion des signalements communautaires.
/// 
/// Fait le lien entre l'application et Firebase Firestore pour stocker 
/// et récupérer les données participatives (retards, contrôleurs, dangers urbains).
class SignalementService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Enregistre un nouvel événement lié au réseau de transport (ex: retard, contrôleur).
  ///
  /// [type] La catégorie du signalement ('retard', 'controleur', etc.).
  /// [stopId] L'identifiant technique de l'arrêt concerné.
  /// [stopName] Le nom lisible de l'arrêt.
  /// [routeId] L'identifiant de la ligne de bus/tram.
  /// [valeur] Donnée optionnelle, utile par exemple pour quantifier un retard en minutes (défaut: 0).
  Future<void> envoyerSignalement({
    required String type,
    required String stopId,
    required String stopName,
    required String routeId,
    int valeur = 0, 
  }) async {
    await _db.collection('signalements').add({
      'type': type,
      'stop_id': stopId,
      'stop_name': stopName,
      'route_id': routeId,
      'valeur': valeur,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Calcule la moyenne des retards signalés sur une ligne et un arrêt spécifiques.
  /// 
  /// Ne prend en compte que les signalements émis au cours des 2 dernières heures 
  /// pour garantir la pertinence de l'information en temps réel.
  Future<int> getMoyenneRetard(String stopId, String routeId) async {
    // Fenêtre glissante de 2 heures
    DateTime deuxHeuresAgo = DateTime.now().subtract(const Duration(hours: 2));

    try {
      QuerySnapshot query = await _db
          .collection('signalements')
          .where('stop_id', isEqualTo: stopId)
          .where('route_id', isEqualTo: routeId)
          .where('type', isEqualTo: 'retard')
          .where('timestamp', isGreaterThan: deuxHeuresAgo)
          .get();

      // Si aucun retard n'a été signalé récemment, la moyenne est de 0
      if (query.docs.isEmpty) return 0;

      int totalRetard = 0;
      for (var doc in query.docs) {
        final data = doc.data() as Map<String, dynamic>;
        totalRetard += (data['valeur'] ?? 0) as int;
      }

      // Retourne la moyenne arrondie à l'entier le plus proche
      return (totalRetard / query.docs.length).round();
    } catch (e) {
      debugPrint("❌ Erreur lors du calcul de la moyenne des retards : $e");
      return 0;
    }
  }

  /// Enregistre un nouveau danger urbain localisé sur la carte.
  ///
  /// [type] L'identifiant textuel du type de danger (issu de l'énumération TypeDanger).
  /// [lat] Latitude exacte du point signalé.
  /// [lng] Longitude exacte du point signalé.
  /// [description] Précisions apportées par l'utilisateur.
  Future<void> envoyerDangerVille({
    required String type,
    required double lat,
    required double lng,
    required String description,
  }) async {
    await _db.collection('dangers_ville').add({
      'type': type,
      'lat': lat,
      'lng': lng,
      'description': description,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Ouvre un flux de données (Stream) sur les signalements de la ville.
  /// 
  /// Permet à l'interface cartographique de se mettre à jour en temps réel 
  /// dès qu'un utilisateur ajoute ou supprime un danger urbain.
  Stream<QuerySnapshot> getDangersVille() {
    return _db.collection('dangers_ville').snapshots();
  }

  /// Vérifie la présence signalée de contrôleurs à un arrêt donné.
  /// 
  /// Un signalement est considéré comme valide (actif) s'il a été émis 
  /// dans les 20 dernières minutes.
  Future<bool> aUneAlerteControleur(String stopId) async {
    // Durée de validité d'une alerte contrôleur
    DateTime limite = DateTime.now().subtract(const Duration(minutes: 20));
    
    try {
      var snap = await _db.collection('signalements')
          .where('stop_id', isEqualTo: stopId)
          .where('type', isEqualTo: 'controleur')
          .where('timestamp', isGreaterThan: limite)
          .get();
          
      // Renvoie true si au moins un document correspond aux critères
      return snap.docs.isNotEmpty;
    } catch (e) {
      debugPrint("❌ Erreur lors de la vérification des alertes contrôleur : $e");
      return false;
    }
  }
}