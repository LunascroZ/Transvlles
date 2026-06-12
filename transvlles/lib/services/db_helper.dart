import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:transvlles/models/gtfs_models.dart';

class DBHelper {
  static Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await initDb();
    return _db!;
  }

  Future<Database> initDb() async {
    String path = join(await getDatabasesPath(), "transvlles.db");
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute("CREATE TABLE routes (route_id TEXT PRIMARY KEY, route_short_name TEXT, route_long_name TEXT, route_color TEXT)");
        await db.execute("CREATE TABLE stops (stop_id TEXT PRIMARY KEY, stop_name TEXT, stop_lat REAL, stop_lon REAL)");
        await db.execute("CREATE TABLE trips (trip_id TEXT PRIMARY KEY, route_id TEXT, trip_headsign TEXT, direction_id INTEGER)");
        await db.execute("CREATE TABLE stop_times (trip_id TEXT, arrival_time TEXT, stop_id TEXT, stop_sequence INTEGER)");

        await _importCSV(db, 'assets/data/routes.txt', 'routes');
        await _importCSV(db, 'assets/data/stops.txt', 'stops');
        await _importCSV(db, 'assets/data/trips.txt', 'trips');
        await _importCSV(db, 'assets/data/stop_times.txt', 'stop_times');
      },
    );
  }

 Future<List<Arret>> getStopsForRoute(String routeId) async {
  final dbClient = await db;
  
  // 1. On cherche d'abord l'ID du trajet qui contient le plus d'arrêts pour cette ligne
  // Cela nous donne la "référence" du parcours complet.
  final List<Map<String, dynamic>> longestTrip = await dbClient.rawQuery('''
    SELECT t.trip_id 
    FROM trips t
    JOIN stop_times st ON t.trip_id = st.trip_id
    WHERE t.route_id = ? AND t.direction_id = 0
    GROUP BY t.trip_id
    ORDER BY COUNT(st.stop_id) DESC
    LIMIT 1
  ''', [routeId]);

  if (longestTrip.isEmpty) return [];

  String tripId = longestTrip.first['trip_id'];

  // 2. On récupère les arrêts de CE trajet précis
  // On garde le GROUP BY sur le nom au cas où il y aurait des micro-doublons
  final List<Map<String, dynamic>> maps = await dbClient.rawQuery('''
    SELECT s.stop_id, s.stop_name, s.stop_lat, s.stop_lon, st.stop_sequence
    FROM stops s
    JOIN stop_times st ON s.stop_id = st.stop_id
    WHERE st.trip_id = ?
    GROUP BY s.stop_name
    ORDER BY st.stop_sequence ASC
  ''', [tripId]);

  return List.generate(maps.length, (i) => Arret.fromMap(maps[i]));
}

  // --- RÉCUPÉRATION DES HORAIRES + TERMINUS DYNAMIQUE ---
  Future<Map<String, dynamic>> getStopTimes(String stopId, String routeId) async {
    final dbClient = await db;
    
    // On cherche tous les horaires pour cet arrêt (Aller et Retour)
    final List<Map<String, dynamic>> results = await dbClient.rawQuery('''
      SELECT st.arrival_time, t.direction_id, t.trip_headsign
      FROM stop_times st
      JOIN trips t ON st.trip_id = t.trip_id
      WHERE t.route_id = ? 
      AND st.stop_id IN (
          SELECT stop_id FROM stops WHERE stop_name = (
              SELECT stop_name FROM stops WHERE stop_id = ?
          )
      )
      GROUP BY st.arrival_time, t.direction_id
      ORDER BY st.arrival_time ASC
    ''', [routeId, stopId]);

    List<Map<String, String>> aller = [];
    List<Map<String, String>> retour = [];
    String terminusAller = "Aller";
    String terminusRetour = "Retour";

    for (var row in results) {
      String time = row['arrival_time'].toString().split(':').take(2).join(':');
      String headsign = row['trip_headsign'] ?? "Terminus";
      
      var data = {"time": time, "dest": headsign};
      
      if (row['direction_id'].toString() == "0") {
        aller.add(data);
        if (terminusAller == "Aller") terminusAller = "Vers $headsign";
      } else {
        retour.add(data);
        if (terminusRetour == "Retour") terminusRetour = "Vers $headsign";
      }
    }

    return {
      "Aller": aller, 
      "Retour": retour, 
      "TerminusAller": terminusAller, 
      "TerminusRetour": terminusRetour
    };
  }

  // --- AUTRES MÉTHODES ---
  Future<void> _importCSV(Database db, String assetPath, String tableName) async {
    final data = await rootBundle.loadString(assetPath);
    List<List<dynamic>> csvTable = const CsvToListConverter().convert(data);
    await db.transaction((txn) async {
      for (var i = 1; i < csvTable.length; i++) {
        final row = csvTable[i];
        if (tableName == 'routes') {
          await txn.insert('routes', {'route_id': row[0], 'route_short_name': row[2], 'route_long_name': row[3], 'route_color': row[7]});
        } else if (tableName == 'stops') {
          await txn.insert('stops', {'stop_id': row[0].toString(), 'stop_name': row[2].toString(), 'stop_lat': double.tryParse(row[4].toString()) ?? 0.0, 'stop_lon': double.tryParse(row[5].toString()) ?? 0.0});
        } else if (tableName == 'trips') {
          int dir = int.tryParse(row[4].toString()) ?? 0;
          await txn.insert('trips', {'route_id': row[0].toString(), 'trip_id': row[2].toString(), 'trip_headsign': row[3].toString(), 'direction_id': dir});
        } else if (tableName == 'stop_times') {
          await txn.insert('stop_times', {'trip_id': row[0].toString(), 'arrival_time': row[1].toString(), 'stop_id': row[3].toString(), 'stop_sequence': int.tryParse(row[4].toString()) ?? 0});
        }
      }
    });
  }

  Future<List<Ligne>> getRoutes(String query) async {
    final dbClient = await db;
    List<Map<String, dynamic>> maps = query.isEmpty 
      ? await dbClient.query('routes') 
      : await dbClient.query('routes', where: "route_short_name LIKE ? OR route_long_name LIKE ?", whereArgs: ['%$query%', '%$query%']);
    return List.generate(maps.length, (i) => Ligne.fromMap(maps[i]));
  }

  Future<List<Arret>> getStops(String query) async {
  final dbClient = await db;
  List<Map<String, dynamic>> maps;

  if (query.isEmpty) {
    // On groupe par nom pour éviter les doublons à l'affichage
    maps = await dbClient.rawQuery('''
      SELECT MIN(stop_id) as stop_id, stop_name, stop_lat, stop_lon 
      FROM stops 
      GROUP BY stop_name 
      ORDER BY stop_name ASC 
      LIMIT 50
    ''');
  } else {
    maps = await dbClient.rawQuery('''
      SELECT MIN(stop_id) as stop_id, stop_name, stop_lat, stop_lon 
      FROM stops 
      WHERE stop_name LIKE ? 
      GROUP BY stop_name 
      ORDER BY stop_name ASC 
      LIMIT 50
    ''', ['%$query%']);
  }

  return List.generate(maps.length, (i) => Arret.fromMap(maps[i]));
}

Future<List<Ligne>> getRoutesForStop(String stopId) async {
  final dbClient = await db;
  
  // La sous-requête (SELECT stop_id FROM stops...) permet de trouver 
  // TOUS les quais qui portent le même nom que celui sur lequel on a cliqué.
  final List<Map<String, dynamic>> maps = await dbClient.rawQuery('''
    SELECT DISTINCT r.* FROM routes r
    JOIN trips t ON r.route_id = t.route_id
    JOIN stop_times st ON t.trip_id = st.trip_id
    WHERE st.stop_id IN (
      SELECT stop_id FROM stops WHERE stop_name = (
        SELECT stop_name FROM stops WHERE stop_id = ?
      )
    )
  ''', [stopId]);

  return List.generate(maps.length, (i) => Ligne.fromMap(maps[i]));
}

Future<List<Arret>> getStopsByIds(List<String> ids) async {
  if (ids.isEmpty) return [];
  final dbClient = await db;
  // Génère une suite de '?' pour le IN (?,?,?)
  String placeholders = List.filled(ids.length, '?').join(',');
  List<Map<String, dynamic>> maps = await dbClient.query(
    'stops',
    where: "stop_id IN ($placeholders)",
    whereArgs: ids,
  );
  return List.generate(maps.length, (i) => Arret.fromMap(maps[i]));
}
}