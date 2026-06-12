import 'package:flutter/material.dart';

class Ligne {
  final String id;
  final String shortName;
  final String longName;
  final Color color;

  Ligne({required this.id, required this.shortName, required this.longName, required this.color});

  // Convertit une ligne SQLite (Map) en objet Dart
  factory Ligne.fromMap(Map<String, dynamic> map) {
    return Ligne(
      id: map['route_id'],
      shortName: map['route_short_name'],
      longName: map['route_long_name'],
      color: Color(int.parse("0xFF${map['route_color']?.toString().isEmpty ?? true ? "808080" : map['route_color']}")),
    );
  }
}

class Arret {
  final String id;
  final String name;
  final double lat;
  final double lon;

  Arret({required this.id, required this.name, required this.lat, required this.lon});

  factory Arret.fromMap(Map<String, dynamic> map) {
    return Arret(
      id: map['stop_id'],
      name: map['stop_name'],
      lat: map['stop_lat'] as double,
      lon: map['stop_lon'] as double,
    );
  }
}