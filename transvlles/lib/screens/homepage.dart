import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:transvlles/services/signalement_service.dart';
import 'package:transvlles/services/db_helper.dart';
import 'package:transvlles/models/gtfs_models.dart';
import 'package:transvlles/screens/afficher_ligne.dart';

/// Énumération des différents types de signalements urbains possibles.
enum TypeDanger { trottoir, eclairage, route, salete, nature, autre }

/// Retourne un libellé lisible par l'utilisateur pour chaque type de signalement.
String labelDanger(TypeDanger t) {
  switch (t) {
    case TypeDanger.trottoir: return 'Trottoir gênant';
    case TypeDanger.eclairage: return 'Éclairage absent';
    case TypeDanger.route: return 'Danger sur la route';
    case TypeDanger.salete: return 'Saleté / dépôt';
    case TypeDanger.nature: return 'Nature proéminente';
    case TypeDanger.autre: return 'Autre';
  }
}

/// Associe une icône spécifique à chaque type de signalement.
IconData iconDanger(TypeDanger t) {
  switch (t) {
    case TypeDanger.trottoir: return Icons.do_not_step;
    case TypeDanger.eclairage: return Icons.lightbulb_outline;
    case TypeDanger.route: return Icons.car_crash;
    case TypeDanger.salete: return Icons.delete_outline;
    case TypeDanger.nature: return Icons.grass;
    case TypeDanger.autre: return Icons.help_outline;
  }
}

/// Associe une couleur thématique à chaque type de signalement.
Color couleurDanger(TypeDanger t) {
  switch (t) {
    case TypeDanger.trottoir: return Colors.orange;
    case TypeDanger.eclairage: return Colors.amber;
    case TypeDanger.route: return Colors.red;
    case TypeDanger.salete: return Colors.brown;
    case TypeDanger.nature: return Colors.green;
    case TypeDanger.autre: return Colors.blueGrey;
  }
}

/// Détermine l'icône appropriée pour un service urbain (vélo, borne de recharge, etc.).
IconData iconService(String amenity) {
  switch (amenity) {
    case 'charging_station': return Icons.ev_station;
    case 'bicycle_parking': return Icons.pedal_bike;
    case 'bicycle_rental': return Icons.electric_scooter;
    case 'drinking_water': return Icons.water_drop;
    case 'fountain': return Icons.water;
    default: return Icons.place;
  }
}

/// Détermine la couleur appropriée pour un marqueur de service urbain.
Color couleurService(String amenity) {
  switch (amenity) {
    case 'charging_station': return Colors.teal;
    case 'bicycle_parking':
    case 'bicycle_rental': return Colors.indigoAccent;
    default: return Colors.lightBlue;
  }
}

/// Représente un espace vert récupéré via l'API OpenStreetMap.
class EspaceVert {
  final LatLng position;
  final String nom;
  final int frequentation;
  EspaceVert(this.position, this.nom, this.frequentation);
}

/// Représente un point d'intérêt ou un service urbain.
class _ServicePoint {
  final LatLng position;
  final String amenity;
  const _ServicePoint(this.position, this.amenity);
}

/// Vue cartographique principale affichant le réseau de transport, 
/// les services urbains et les signalements communautaires.
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final mapController = MapController();
  LatLng? maPosition;
  bool chargementPosition = false;
  double zoom = 13;

  List<EspaceVert> espacesVerts = [];
  List<_ServicePoint> servicesVille = [];
  List<Arret> arrretsTransit = [];

  bool afficherEspacesVerts = true;
  bool afficherServices = true;
  bool afficherBusStops = true;

  // Délimitation géographique pour restreindre les requêtes OpenStreetMap
  static const zone = '50.32,3.45,50.38,3.58';
  static const cles = ['charging_station', 'bicycle_parking', 'bicycle_rental', 'drinking_water', 'fountain'];

  @override
  void initState() {
    super.initState();
    _chargerCarte();
    _chargerArretsTransit();
  }

  /// Charge les arrêts de transport en commun depuis la base de données locale (SQLite).
  Future<void> _chargerArretsTransit() async {
    try {
      // --- MODIFICATION ICI : On utilise la nouvelle fonction sans limite ---
      final data = await DBHelper().getAllStopsForMap(); 
      
      debugPrint("🚌 Arrêts chargés depuis la base de données locale : ${data.length}");
      if (mounted) {
        setState(() {
          arrretsTransit = data;
        });
      }
    } catch (e) {
      debugPrint("❌ Erreur lors du chargement SQL des arrêts : $e");
    }
  }

  /// Interroge l'API Overpass pour récupérer les espaces verts et les services urbains.
  Future<void> _chargerCarte() async {
    final corps = StringBuffer();
    for (final s in cles) { corps.write('node["amenity"="$s"]($zone);'); }
    corps..write('way["leisure"="park"]($zone);')..write('way["landuse"="forest"]($zone);')..write('way["natural"="wood"]($zone);');
    final requete = '[out:json];($corps);out center;';

    var reponse = await _overpass(requete);
    if (reponse == null) {
      // Mécanisme de relance basique en cas d'échec temporaire de l'API
      await Future.delayed(const Duration(seconds: 2));
      reponse = await _overpass(requete);
    }
    if (reponse == null) return;

    final points = <_ServicePoint>[];
    final verts = <EspaceVert>[];
    
    for (final e in reponse) {
      final tags = e['tags'] as Map?;
      if (tags == null) continue;

      final amenity = tags['amenity'];
      if (amenity != null && cles.contains(amenity) && e['lat'] != null && e['lon'] != null) {
        points.add(_ServicePoint(LatLng((e['lat'] as num).toDouble(), (e['lon'] as num).toDouble()), amenity as String));
        continue;
      }
      
      final centre = e['center'];
      if (centre != null) {
        final nom = (tags['name'] ?? 'Espace vert').toString();
        // Estimation arbitraire de la fréquentation basée sur les métadonnées (faute de flux temps réel)
        final freq = (nom.length + (e['id'] as int? ?? 0)) % 3;
        verts.add(EspaceVert(LatLng((centre['lat'] as num).toDouble(), (centre['lon'] as num).toDouble()), nom, freq));
      }
    }
    
    debugPrint("🌳 Espaces verts récupérés : ${verts.length}");
    debugPrint("🚲 Services urbains récupérés : ${points.length}");
    
    if (mounted) {
      setState(() { 
        servicesVille = points; 
        espacesVerts = verts; 
      });
    }
  }

  /// Exécute une requête HTTP POST vers l'API Overpass (OpenStreetMap).
  /// Utilise un User-Agent personnalisé pour respecter les conditions d'utilisation 
  /// de l'API publique et éviter les erreurs HTTP 406.
  Future<List?> _overpass(String requete) async {
    try {
      final url = Uri.parse('https://overpass-api.de/api/interpreter');
      
      final r = await http.post(
        url,
        headers: {
          'User-Agent': 'TransvllesApp/1.0 (Projet Etudiant Valenciennes)',
          'Accept': 'application/json',
        },
        body: {
          'data': requete
        },
      ).timeout(const Duration(seconds: 15)); 
      
      if (r.statusCode != 200) {
        debugPrint("⚠️ Erreur API Overpass - Code HTTP : ${r.statusCode}");
        return null;
      }
      
      return jsonDecode(r.body)['elements'] as List;
    } catch (e) {
      debugPrint("❌ Exception réseau lors de l'appel Overpass : $e");
      return null;
    }
  }

  /// Demande les autorisations de localisation et centre la caméra sur l'utilisateur.
  Future<void> _allerVersMaPosition() async {
    setState(() => chargementPosition = true);
    
    bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      setState(() => chargementPosition = false);
      return;
    }
    
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      setState(() => chargementPosition = false);
      return;
    }
    
    final pos = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    
    setState(() {
      maPosition = LatLng(pos.latitude, pos.longitude);
      chargementPosition = false;
    });
    mapController.move(maPosition!, 16);
  }

  /// Affiche le formulaire de création d'un signalement aux coordonnées spécifiées.
  void _nouveauSignalement(LatLng position) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FeuilleAjout(position: position),
    );
  }

  /// Récupère et affiche les lignes de transport desservant l'arrêt sélectionné.
  void _ouvrirArretTransit(Arret arret) async {
    final lignes = await DBHelper().getRoutesForStop(arret.id);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(color: Colors.grey[900], borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 20),
            Row(
              children: [
                const CircleAvatar(backgroundColor: Colors.pink, child: Icon(Icons.directions_bus, color: Colors.white)),
                const SizedBox(width: 12),
                Expanded(child: Text(arret.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))),
              ],
            ),
            const SizedBox(height: 16),
            const Text("Lignes desservant cet arrêt :", style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: lignes.length,
                itemBuilder: (context, i) => ListTile(
                  leading: CircleAvatar(backgroundColor: lignes[i].color, child: Text(lignes[i].shortName, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold))),
                  title: Text(lignes[i].longName, style: const TextStyle(color: Colors.white)),
                  trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14),
                  onTap: () { 
                    Navigator.pop(context); // Ferme la pop-up de la carte
                    
                    // Redirection intelligente vers l'onglet Transports
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AfficherLigne(
                          // On injecte le nom court de la ligne (ex: "T1", "S1") directement dans la barre de recherche
                          rechercheInitiale: lignes[i].shortName, 
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Affiche les détails d'un signalement communautaire et permet de l'archiver via Firebase.
  void _afficherDetailsDanger(String docId, Map<String, dynamic> data, TypeDanger type) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(color: Colors.grey[900], borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 20),
            Row(
              children: [
                CircleAvatar(backgroundColor: couleurDanger(type).withValues(alpha: 0.3), child: Icon(iconDanger(type), color: couleurDanger(type))),
                const SizedBox(width: 12),
                Expanded(child: Text(labelDanger(type), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))),
              ],
            ),
            const SizedBox(height: 16),
            const Text("Description du problème :", style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 6),
            Text(data['description'] ?? 'Aucune description.', style: const TextStyle(color: Colors.white, fontSize: 15)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () async {
                await FirebaseFirestore.instance.collection('dangers_ville').doc(docId).delete();
                if (!mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Problème archivé / résolu !'), backgroundColor: Colors.green));
              },
              style: FilledButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.check_circle, color: Colors.white),
              label: const Text('Marquer comme résolu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  /// Affiche les informations descriptives d'une infrastructure de service urbain.
  void _infoService(_ServicePoint p) {
    String titre = '';
    String desc = '';
    switch (p.amenity) {
      case 'charging_station': titre = 'Borne de recharge'; desc = 'Station de recharge pour véhicules électriques.'; break;
      case 'bicycle_parking': titre = 'Parking à vélos'; desc = 'Espace de stationnement pour deux-roues.'; break;
      case 'bicycle_rental': titre = 'Location de vélos'; desc = 'Station de vélos en libre-service.'; break;
      case 'drinking_water': titre = 'Point d\'eau'; desc = 'Eau potable accessible au public.'; break;
      case 'fountain': titre = 'Fontaine'; desc = 'Point d\'eau décoratif ou rafraîchissant.'; break;
      default: titre = 'Service urbain'; desc = 'Infrastructure publique.';
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(color: Colors.grey[900], borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 20),
            Row(
              children: [
                CircleAvatar(backgroundColor: couleurService(p.amenity).withValues(alpha: 0.3), child: Icon(iconService(p.amenity), color: couleurService(p.amenity))),
                const SizedBox(width: 12),
                Expanded(child: Text(titre, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))),
              ],
            ),
            const SizedBox(height: 16),
            Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  /// Affiche les statistiques ou détails liés à un espace vert sélectionné.
  void _infoEspaceVert(EspaceVert e) {
    const labels = ['Calme, peu de monde', 'Fréquentation modérée', 'Très fréquenté'];
    const couleurs = [Colors.green, Colors.orange, Colors.red];
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(color: Colors.grey[900], borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 20),
            Row(
              children: [
                const CircleAvatar(backgroundColor: Colors.greenAccent, child: Icon(Icons.park, color: Colors.green)),
                const SizedBox(width: 12),
                Expanded(child: Text(e.nom, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))),
              ],
            ),
            const SizedBox(height: 16),
            const Row(children: [
              Icon(Icons.ac_unit, color: Colors.greenAccent, size: 20),
              SizedBox(width: 10),
              Expanded(child: Text('Îlot de fraîcheur : moins de chaleur, de bruit et de CO₂.', style: TextStyle(color: Colors.white70))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.groups, color: couleurs[e.frequentation], size: 20),
              const SizedBox(width: 10),
              Text('${labels[e.frequentation]} (estimé)', style: const TextStyle(color: Colors.white70)),
            ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: Stack(
        children: [
          // Composant cartographique de base
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: const LatLng(50.35, 3.515),
              initialZoom: 13,
              onPositionChanged: (camera, _) {
                double currentZoom = camera.zoom ?? 13.0;
                // Optimisation des rendus conditionnels selon le niveau de zoom
                if ((currentZoom >= 14) != (zoom >= 14)) setState(() {});
                zoom = currentZoom;
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.transvlles',
              ),
              
              // Calque des zones d'espaces verts
              if (afficherEspacesVerts)
                CircleLayer(
                  circles: espacesVerts.map((e) => CircleMarker(
                    point: e.position,
                    radius: 90,
                    useRadiusInMeter: true,
                    color: Colors.green.withValues(alpha: 0.2),
                    borderColor: Colors.green.withValues(alpha: 0.5),
                    borderStrokeWidth: 1.5,
                  )).toList(),
                ),
              
              // Marqueurs interactifs des parcs
              if (afficherEspacesVerts)
                MarkerLayer(markers: espacesVerts.map((e) => Marker(point: e.position, width: 34, height: 34, child: _Dot(icon: Icons.park, color: Colors.green, onTap: () => _infoEspaceVert(e)))).toList()),
              
              // Marqueurs des services urbains (restreint au zoom détaillé)
              if (afficherServices && zoom >= 14)
                MarkerLayer(markers: servicesVille.map((p) => Marker(
                  point: p.position, 
                  width: 30, 
                  height: 30, 
                  child: _Dot(
                    icon: iconService(p.amenity), 
                    color: couleurService(p.amenity), 
                    small: true, 
                    onTap: () => _infoService(p)
                  )
                )).toList()),
              
              // Marqueurs de la base de données de transport locale
              if (afficherBusStops && zoom >=14) 
                MarkerLayer(
                  markers: arrretsTransit.map((arret) => Marker(
                    point: LatLng(arret.lat, arret.lon),
                    width: 32, height: 32,
                    child: GestureDetector(
                      onTap: () => _ouvrirArretTransit(arret),
                      child: Container(
                        decoration: const BoxDecoration(color: Colors.pink, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 4)]),
                        child: const Icon(Icons.directions_bus, color: Colors.white, size: 16),
                      ),
                    ),
                  )).toList(),
                ),

              // Souscription au flux Firebase pour l'affichage en temps réel des signalements
              StreamBuilder<QuerySnapshot>(
                stream: SignalementService().getDangersVille(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const MarkerLayer(markers: []);
                  
                  List<Marker> markersFirebase = snapshot.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    TypeDanger type = TypeDanger.values.firstWhere((e) => e.name == data['type'], orElse: () => TypeDanger.autre);
                    return Marker(
                      point: LatLng(data['lat'], data['lng']),
                      width: 42, height: 50,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: () => _afficherDetailsDanger(doc.id, data, type),
                        child: _Pin(icon: iconDanger(type), color: couleurDanger(type)),
                      ),
                    );
                  }).toList();
                  
                  return MarkerLayer(markers: markersFirebase);
                },
              ),

              if (maPosition != null)
                MarkerLayer(markers: [Marker(point: maPosition!, width: 26, height: 26, child: const _MyLocationDot())]),
            ],
          ),

          // Réticule de visée central pour faciliter la création précise de signalements
          IgnorePointer(
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(color: Colors.pink, shape: BoxShape.circle),
                  ),
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.pink.withValues(alpha: 0.5), width: 2),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // En-tête de navigation
          Positioned(
            top: topPad + 12, left: 16, right: 16,
            child: Material(
              color: Colors.grey[850],
              borderRadius: BorderRadius.circular(18),
              elevation: 5,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const CircleAvatar(backgroundColor: Colors.pinkAccent, child: Icon(Icons.eco, color: Colors.white)),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Transvlles · Ville', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                        Text('Confort urbain & Réseau', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Menu latéral de filtrage
          Positioned(
            right: 16, top: topPad + 92,
            child: Material(
              color: Colors.grey[850],
              borderRadius: BorderRadius.circular(16),
              elevation: 5,
              child: Column(
                children: [
                  IconButton(
                    onPressed: chargementPosition ? null : _allerVersMaPosition,
                    icon: chargementPosition ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.pink)) : const Icon(Icons.my_location, color: Colors.white),
                  ),
                  const Divider(height: 1, color: Colors.grey),
                  IconButton(
                    onPressed: () => setState(() => afficherEspacesVerts = !afficherEspacesVerts),
                    icon: Icon(afficherEspacesVerts ? Icons.park : Icons.park_outlined, color: afficherEspacesVerts ? Colors.green : Colors.grey),
                  ),
                  const Divider(height: 1, color: Colors.grey),
                  IconButton(
                    onPressed: () => setState(() => afficherServices = !afficherServices),
                    icon: Icon(afficherServices ? Icons.pedal_bike : Icons.pedal_bike_outlined, color: afficherServices ? Colors.blueAccent : Colors.grey),
                  ),
                  const Divider(height: 1, color: Colors.grey),
                  IconButton(
                    onPressed: () => setState(() => afficherBusStops = !afficherBusStops),
                    icon: Icon(afficherBusStops ? Icons.directions_bus : Icons.directions_bus_outlined, color: afficherBusStops ? Colors.pink : Colors.grey),
                  ),
                ],
              ),
            ),
          ),

          // Bouton d'action principal ancré au réticule de visée
          Positioned(
            left: 16, right: 16, bottom: MediaQuery.of(context).padding.bottom + 16,
            child: FilledButton.icon(
              onPressed: () => _nouveauSignalement(mapController.camera.center),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.pink,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.add_alert, color: Colors.white),
              label: const Text('Signaler ce point', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Composant visuel représentant un marqueur de signalement urbain.
class _Pin extends StatelessWidget {
  final IconData icon; 
  final Color color;
  
  const _Pin({required this.icon, required this.color});
  
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38, height: 38, 
          decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)]), 
          child: Icon(icon, color: Colors.white, size: 20)
        ),
        Transform.translate(
          offset: const Offset(0, -3), 
          child: Transform.rotate(
            angle: 0.785398, 
            child: Container(width: 10, height: 10, color: color)
          )
        ),
      ],
    );
  }
}

/// Composant visuel générique pour les points d'intérêts secondaires.
class _Dot extends StatelessWidget {
  final IconData icon; 
  final Color color; 
  final bool small; 
  final VoidCallback? onTap;
  
  const _Dot({required this.icon, required this.color, this.small = false, this.onTap});
  
  @override
  Widget build(BuildContext context) {
    final size = small ? 28.0 : 34.0;
    return GestureDetector(
      onTap: onTap, 
      child: Container(
        width: size, height: size, 
        decoration: BoxDecoration(color: Colors.grey[850], shape: BoxShape.circle, border: Border.all(color: color, width: 2), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)]), 
        child: Icon(icon, color: color, size: small ? 16 : 20)
      )
    );
  }
}

/// Indicateur visuel de la géolocalisation de l'utilisateur.
class _MyLocationDot extends StatelessWidget {
  const _MyLocationDot();
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.pink, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)]
      )
    );
  }
}

/// Formulaire interactif permettant la création et l'envoi d'un signalement à Firestore.
class FeuilleAjout extends StatefulWidget {
  final LatLng position;
  const FeuilleAjout({super.key, required this.position});
  
  @override
  State<FeuilleAjout> createState() => _FeuilleAjoutState();
}

class _FeuilleAjoutState extends State<FeuilleAjout> {
  TypeDanger type = TypeDanger.trottoir;
  final description = TextEditingController();

  /// Valide les données saisies et transmet la requête de création au service Firebase.
  void _envoyer() async {
    if (description.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La description du danger est requise.')));
      return;
    }
    
    await SignalementService().envoyerDangerVille(
      type: type.name, 
      lat: widget.position.latitude, 
      lng: widget.position.longitude, 
      description: description.text.trim()
    );
    
    if (!mounted) return;
    
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signalement transmis au cloud avec succès.'), backgroundColor: Colors.pink));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.grey[900], borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
      padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(10)))),
          const SizedBox(height: 20),
          const Text('Signaler un danger', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.pink)),
          const SizedBox(height: 18),
          
          Wrap(
            spacing: 8, runSpacing: 8,
            children: TypeDanger.values.map((t) => ChoiceChip(
              backgroundColor: Colors.grey[800], selectedColor: couleurDanger(t).withValues(alpha: 0.3),
              side: BorderSide(color: t == type ? couleurDanger(t) : Colors.transparent),
              avatar: Icon(iconDanger(t), size: 18, color: t == type ? couleurDanger(t) : Colors.grey),
              label: Text(labelDanger(t), style: TextStyle(color: t == type ? Colors.white : Colors.grey)),
              selected: t == type, onSelected: (_) => setState(() => type = t),
            )).toList(),
          ),
          
          const SizedBox(height: 18),
          TextField(
            controller: description, 
            style: const TextStyle(color: Colors.white), 
            maxLines: 3, 
            decoration: InputDecoration(
              labelText: 'Description', 
              labelStyle: const TextStyle(color: Colors.grey), 
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey[700]!)), 
              focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.pink))
            )
          ),
          
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _envoyer, 
            style: FilledButton.styleFrom(backgroundColor: Colors.pink, minimumSize: const Size.fromHeight(50)), 
            icon: const Icon(Icons.send, color: Colors.white), 
            label: const Text('Soumettre le signalement', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );
  }
}
