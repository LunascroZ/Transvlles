import 'package:cloud_firestore/cloud_firestore.dart';

class SignalementService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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

  // MÉTHODE pour calculer la moyenne de retard des 2 dernières heures
  Future<int> getMoyenneRetard(String stopId, String routeId) async {
    DateTime deuxHeuresAgo = DateTime.now().subtract(const Duration(hours: 2));

    try {
      QuerySnapshot query = await _db
          .collection('signalements')
          .where('stop_id', isEqualTo: stopId)
          .where('route_id', isEqualTo: routeId)
          .where('type', isEqualTo: 'retard')
          .where('timestamp', isGreaterThan: deuxHeuresAgo)
          .get();

      if (query.docs.isEmpty) return 0;

      int totalRetard = 0;
      for (var doc in query.docs) {
        final data = doc.data() as Map<String, dynamic>;
        totalRetard += (data['valeur'] ?? 0) as int;
      }

      return (totalRetard / query.docs.length).round();
    } catch (e) {
      return 0;
    }
  }
  Future<bool> aUneAlerteControleur(String stopId) async {
  // On considère une alerte valide pendant 20 minutes
  DateTime limite = DateTime.now().subtract(const Duration(minutes: 20));
  
  try {
    var snap = await _db.collection('signalements')
        .where('stop_id', isEqualTo: stopId)
        .where('type', isEqualTo: 'controleur')
        .where('timestamp', isGreaterThan: limite)
        .get();
    return snap.docs.isNotEmpty;
  } catch (e) {
    print("❌ Erreur moyenne retard: $e");
    return false;
  }
}
}