import 'package:flutter/material.dart';

/// Modèle de données représentant une ligne de transport en commun (bus, tramway).
/// 
/// La structure de cet objet est alignée sur la spécification internationale GTFS 
/// (General Transit Feed Specification) pour la table "routes".
class Ligne {
  final String id;
  final String shortName;
  final String longName;
  final Color color;

  Ligne({
    required this.id, 
    required this.shortName, 
    required this.longName, 
    required this.color,
  });

  /// Construit une instance de [Ligne] à partir d'un dictionnaire (Map) 
  /// extrait de la base de données locale (SQLite).
  /// 
  /// Traite dynamiquement le champ 'route_color' fourni au format hexadécimal.
  /// Si la couleur est absente ou invalide dans les données sources, 
  /// une couleur grise de secours (0xFF808080) est automatiquement appliquée.
  factory Ligne.fromMap(Map<String, dynamic> map) {
    final colorHex = map['route_color']?.toString() ?? '';
    final validHex = colorHex.isEmpty ? "808080" : colorHex;

    return Ligne(
      id: map['route_id']?.toString() ?? '',
      shortName: map['route_short_name']?.toString() ?? '',
      longName: map['route_long_name']?.toString() ?? '',
      color: Color(int.parse("0xFF$validHex")),
    );
  }
}

/// Modèle de données représentant un point d'arrêt physique sur le réseau.
/// 
/// La structure de cet objet est alignée sur la spécification internationale GTFS 
/// pour la table "stops".
class Arret {
  final String id;
  final String name;
  final double lat;
  final double lon;

  Arret({
    required this.id, 
    required this.name, 
    required this.lat, 
    required this.lon,
  });

  /// Construit une instance d'[Arret] à partir d'un dictionnaire (Map) 
  /// extrait de la base de données locale (SQLite).
  factory Arret.fromMap(Map<String, dynamic> map) {
    return Arret(
      id: map['stop_id']?.toString() ?? '',
      name: map['stop_name']?.toString() ?? '',
      // Utilisation du cast as num? pour prévenir les erreurs si SQLite renvoie un entier (int) au lieu d'un double
      lat: (map['stop_lat'] as num?)?.toDouble() ?? 0.0,
      lon: (map['stop_lon'] as num?)?.toDouble() ?? 0.0,
    );
  }
}