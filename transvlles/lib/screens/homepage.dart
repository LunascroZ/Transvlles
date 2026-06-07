import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

// Les types de dangers que les usagers peuvent signaler en ville.
enum TypeDanger { trottoir, eclairage, route, salete, nature, autre }

String labelDanger(TypeDanger t) {
  switch (t) {
    case TypeDanger.trottoir:
      return 'Trottoir gênant';
    case TypeDanger.eclairage:
      return 'Éclairage absent';
    case TypeDanger.route:
      return 'Danger sur la route';
    case TypeDanger.salete:
      return 'Saleté / dépôt';
    case TypeDanger.nature:
      return 'Nature proéminente';
    case TypeDanger.autre:
      return 'Autre';
  }
}

IconData iconDanger(TypeDanger t) {
  switch (t) {
    case TypeDanger.trottoir:
      return Icons.do_not_step;
    case TypeDanger.eclairage:
      return Icons.lightbulb_outline;
    case TypeDanger.route:
      return Icons.car_crash;
    case TypeDanger.salete:
      return Icons.delete_outline;
    case TypeDanger.nature:
      return Icons.grass;
    case TypeDanger.autre:
      return Icons.help_outline;
  }
}

Color couleurDanger(TypeDanger t) {
  switch (t) {
    case TypeDanger.trottoir:
      return const Color(0xFFEF6C00); // orange
    case TypeDanger.eclairage:
      return const Color(0xFFF9A825); // ambre
    case TypeDanger.route:
      return const Color(0xFFD32F2F); // rouge
    case TypeDanger.salete:
      return const Color(0xFF6D4C41); // marron
    case TypeDanger.nature:
      return const Color(0xFF2E7D32); // vert
    case TypeDanger.autre:
      return const Color(0xFF546E7A); // bleu-gris
  }
}

// Services utiles affichés sur la carte (parkings vélo, recharge, eau...).
IconData iconService(String amenity) {
  switch (amenity) {
    case 'charging_station':
      return Icons.ev_station;
    case 'bicycle_parking':
      return Icons.pedal_bike;
    case 'bicycle_rental':
      return Icons.electric_scooter;
    case 'drinking_water':
      return Icons.water_drop;
    case 'fountain':
      return Icons.water;
    default:
      return Icons.place;
  }
}

Color couleurService(String amenity) {
  switch (amenity) {
    case 'charging_station':
      return const Color(0xFF00897B); // teal
    case 'bicycle_parking':
    case 'bicycle_rental':
      return const Color(0xFF3949AB); // indigo
    default:
      return const Color(0xFF0288D1); // bleu (eau)
  }
}

// Un commentaire sous un signalement.
// Une réponse qui obtient plus de likes que le commentaire de base le "ratio" :
// le commentaire de base est alors archivé.
class Commentaire {
  final String auteur;
  final String texte;
  int likes = 0;
  bool jaime = false;
  final List<Commentaire> reponses = [];

  Commentaire(this.auteur, this.texte);

  bool get estRatio => reponses.any((r) => r.likes > likes);
}

class Signalement {
  final TypeDanger type;
  final LatLng position;
  final String description;
  final String auteur;
  final DateTime date;
  int votes;
  bool jaiVote = false;
  bool resolu = false;
  final List<Commentaire> commentaires = [];

  Signalement({
    required this.type,
    required this.position,
    required this.description,
    required this.auteur,
    required this.date,
    this.votes = 0,
  });
}

// Un espace vert (parc, bois) récupéré sur OpenStreetMap.
class EspaceVert {
  final LatLng position;
  final String nom;
  final int frequentation; // 0 calme, 1 moyen, 2 fréquenté

  EspaceVert(this.position, this.nom, this.frequentation);
}

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

  final List<Signalement> signalements = [];
  List<EspaceVert> espacesVerts = [];
  List<_ServicePoint> servicesVille = [];
  bool afficherEspacesVerts = true;
  bool afficherServices = true;

  // Zone autour de Valenciennes pour les requêtes OpenStreetMap.
  static const zone = '50.32,3.45,50.38,3.58';
  static const cles = [
    'charging_station',
    'bicycle_parking',
    'bicycle_rental',
    'drinking_water',
    'fountain',
  ];

  @override
  void initState() {
    super.initState();
    _exemplesSignalements();
    _chargerCarte();
  }

  // Quelques signalements de démonstration au lancement.
  void _exemplesSignalements() {
    final maintenant = DateTime.now();
    final s1 = Signalement(
      type: TypeDanger.eclairage,
      position: const LatLng(50.3585, 3.5210),
      description: 'Lampadaire éteint depuis plusieurs jours, rue très sombre le soir.',
      auteur: 'Camille',
      date: maintenant.subtract(const Duration(hours: 5)),
      votes: 7,
    );
    s1.commentaires.add(Commentaire('Léo', 'Confirmé, je suis tombé hier à cause du noir.')..likes = 2);

    signalements.addAll([
      s1,
      Signalement(
        type: TypeDanger.trottoir,
        position: const LatLng(50.3520, 3.5150),
        description: 'Poubelles en plein milieu du trottoir, impossible de passer en poussette.',
        auteur: 'Sofia',
        date: maintenant.subtract(const Duration(days: 1)),
        votes: 3,
      ),
      Signalement(
        type: TypeDanger.nature,
        position: const LatLng(50.3470, 3.5080),
        description: 'Haie débordante, on doit marcher sur la route pour passer.',
        auteur: 'Hugo',
        date: maintenant.subtract(const Duration(days: 2)),
        votes: 1,
      ),
    ]);
  }

  // Une seule requête Overpass pour les services ET les espaces verts :
  // ça évite les limitations de débit de deux appels simultanés.
  Future<void> _chargerCarte() async {
    final corps = StringBuffer();
    for (final s in cles) {
      corps.write('node["amenity"="$s"]($zone);');
    }
    corps
      ..write('way["leisure"="park"]($zone);')
      ..write('way["landuse"="forest"]($zone);')
      ..write('way["natural"="wood"]($zone);');
    final requete = '[out:json];($corps);out center;';

    var reponse = await _overpass(requete);
    if (reponse == null) {
      // Overpass limite parfois les requêtes : on réessaie une fois.
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
      if (amenity != null &&
          cles.contains(amenity) &&
          e['lat'] != null &&
          e['lon'] != null) {
        points.add(_ServicePoint(
          LatLng((e['lat'] as num).toDouble(), (e['lon'] as num).toDouble()),
          amenity as String,
        ));
        continue;
      }

      final centre = e['center'];
      if (centre != null) {
        final nom = (tags['name'] ?? 'Espace vert').toString();
        // On n'a pas de vraie donnée de fréquentation : on l'estime.
        final freq = (nom.length + (e['id'] as int? ?? 0)) % 3;
        verts.add(EspaceVert(
          LatLng((centre['lat'] as num).toDouble(),
              (centre['lon'] as num).toDouble()),
          nom,
          freq,
        ));
      }
    }

    if (mounted) {
      setState(() {
        servicesVille = points;
        espacesVerts = verts;
      });
    }
  }

  // Petit utilitaire pour interroger l'API Overpass d'OpenStreetMap.
  Future<List?> _overpass(String requete) async {
    final url = Uri.parse(
      'https://overpass-api.de/api/interpreter?data=${Uri.encodeComponent(requete)}',
    );
    try {
      final r = await http.get(url);
      if (r.statusCode != 200) return null;
      return jsonDecode(r.body)['elements'] as List;
    } catch (_) {
      return null;
    }
  }

  Future<void> _allerVersMaPosition() async {
    setState(() => chargementPosition = true);

    if (!await Geolocator.isLocationServiceEnabled()) {
      _message('Active la localisation sur ton appareil.');
      setState(() => chargementPosition = false);
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _message('Permission de localisation refusée.');
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

  void _message(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // --- Signalements ---

  Future<void> _nouveauSignalement(LatLng position) async {
    final signalement = await showModalBottomSheet<Signalement>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FeuilleAjout(position: position),
    );
    if (signalement == null) return;
    setState(() => signalements.insert(0, signalement));
    mapController.move(position, zoom < 15 ? 15 : zoom);
    _message('Signalement ajouté, merci 🙌');
  }

  void _ouvrirSignalement(Signalement s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FeuilleDetail(
        signalement: s,
        onMaj: () => setState(() {}),
      ),
    );
  }

  void _listeSignalements() {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: cs.error),
                  const SizedBox(width: 10),
                  const Text('Signalements en ville',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
            ),
            if (signalements.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Aucun signalement pour le moment.')),
              ),
            for (final s in signalements)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                leading: CircleAvatar(
                  backgroundColor: couleurDanger(s.type).withValues(alpha: 0.15),
                  child: Icon(iconDanger(s.type), color: couleurDanger(s.type)),
                ),
                title: Text(
                  labelDanger(s.type),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    decoration: s.resolu ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: Text(s.description,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.thumb_up_alt_outlined, size: 16, color: cs.primary),
                    Text('${s.votes}'),
                  ],
                ),
                onTap: () {
                  Navigator.pop(context);
                  mapController.move(s.position, 16);
                  _ouvrirSignalement(s);
                },
              ),
          ],
        ),
      ),
    );
  }

  // --- Espaces verts ---

  void _infoEspaceVert(EspaceVert e) {
    const labels = ['Calme, peu de monde', 'Fréquentation modérée', 'Très fréquenté'];
    const couleurs = [Color(0xFF2E7D32), Color(0xFFEF6C00), Color(0xFFD32F2F)];
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFE6F4EA),
                  child: Icon(Icons.park, color: Color(0xFF2E7D32)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(e.nom,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Row(children: [
              Icon(Icons.ac_unit, color: Color(0xFF2E7D32), size: 20),
              SizedBox(width: 10),
              Expanded(child: Text('Îlot de fraîcheur : moins de chaleur, de bruit et de CO₂.')),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.groups, color: couleurs[e.frequentation], size: 20),
              const SizedBox(width: 10),
              Text('${labels[e.frequentation]} (estimé)'),
            ]),
          ],
        ),
      ),
    );
  }

  // --- Marqueurs ---

  List<Marker> _marqueursSignalements() {
    return [
      for (final s in signalements)
        Marker(
          point: s.position,
          width: 42,
          height: 50,
          alignment: Alignment.topCenter,
          child: _Pin(
            icon: iconDanger(s.type),
            color: couleurDanger(s.type),
            faded: s.resolu,
            onTap: () => _ouvrirSignalement(s),
          ),
        ),
    ];
  }

  List<Marker> _marqueursEspacesVerts() {
    return [
      for (final e in espacesVerts)
        Marker(
          point: e.position,
          width: 34,
          height: 34,
          child: _Dot(
            icon: Icons.park,
            color: const Color(0xFF2E7D32),
            onTap: () => _infoEspaceVert(e),
          ),
        ),
    ];
  }

  List<Marker> _marqueursServices() {
    return [
      for (final p in servicesVille)
        Marker(
          point: p.position,
          width: 30,
          height: 30,
          child: _Dot(
            icon: iconService(p.amenity),
            color: couleurService(p.amenity),
            small: true,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final detaille = zoom >= 14; // détails affichés seulement en zoomant
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: const LatLng(50.35, 3.515),
              initialZoom: 13,
              onLongPress: (_, point) => _nouveauSignalement(point),
              onPositionChanged: (camera, _) {
                if ((camera.zoom >= 14) != detaille) setState(() {});
                zoom = camera.zoom;
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.transvlles',
              ),
              if (afficherEspacesVerts)
                CircleLayer(
                  circles: [
                    for (final e in espacesVerts)
                      CircleMarker(
                        point: e.position,
                        radius: 90,
                        useRadiusInMeter: true,
                        color: const Color(0xFF2E7D32).withValues(alpha: 0.16),
                        borderColor: const Color(0xFF2E7D32).withValues(alpha: 0.5),
                        borderStrokeWidth: 1.5,
                      ),
                  ],
                ),
              if (afficherEspacesVerts)
                MarkerLayer(markers: _marqueursEspacesVerts()),
              if (afficherServices && detaille)
                MarkerLayer(markers: _marqueursServices()),
              MarkerLayer(markers: _marqueursSignalements()),
              if (maPosition != null)
                MarkerLayer(markers: [
                  Marker(
                    point: maPosition!,
                    width: 26,
                    height: 26,
                    child: const _MyLocationDot(),
                  ),
                ]),
            ],
          ),

          // En-tête flottant
          Positioned(
            top: topPad + 12,
            left: 16,
            right: 16,
            child: _HeaderCard(),
          ),

          // Contrôles à droite (localisation + filtres)
          Positioned(
            right: 16,
            top: topPad + 92,
            child: _ControlBar(
              chargement: chargementPosition,
              onPosition: chargementPosition ? null : _allerVersMaPosition,
              espacesVerts: afficherEspacesVerts,
              onEspacesVerts: () =>
                  setState(() => afficherEspacesVerts = !afficherEspacesVerts),
              services: afficherServices,
              onServices: () =>
                  setState(() => afficherServices = !afficherServices),
            ),
          ),

          // Barre d'actions en bas
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _listeSignalements,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      backgroundColor: cs.surface,
                      side: BorderSide(color: cs.outlineVariant),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.list_alt),
                    label: Text('Liste (${signalements.length})'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _nouveauSignalement(mapController.camera.center),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.add_alert),
                    label: const Text('Signaler'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServicePoint {
  final LatLng position;
  final String amenity;
  const _ServicePoint(this.position, this.amenity);
}

// En-tête flottant avec le titre de l'app.
class _HeaderCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(18),
      shadowColor: Colors.black26,
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: cs.primaryContainer,
              child: Icon(Icons.eco, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Transville · Ville',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                Text('Confort urbain · Valenciennes',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Aide',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    behavior: SnackBarBehavior.floating,
                    content: Text('Appui long sur la carte pour signaler un danger.'),
                  ),
                );
              },
              icon: Icon(Icons.info_outline, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// Colonne de boutons ronds à droite de la carte.
class _ControlBar extends StatelessWidget {
  final bool chargement;
  final VoidCallback? onPosition;
  final bool espacesVerts;
  final VoidCallback onEspacesVerts;
  final bool services;
  final VoidCallback onServices;

  const _ControlBar({
    required this.chargement,
    required this.onPosition,
    required this.espacesVerts,
    required this.onEspacesVerts,
    required this.services,
    required this.onServices,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(16),
      shadowColor: Colors.black26,
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            IconButton(
              tooltip: 'Ma position',
              onPressed: onPosition,
              icon: chargement
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
            ),
            _Sep(),
            IconButton(
              tooltip: 'Espaces verts',
              onPressed: onEspacesVerts,
              isSelected: espacesVerts,
              icon: const Icon(Icons.park_outlined),
              selectedIcon: const Icon(Icons.park, color: Color(0xFF2E7D32)),
            ),
            _Sep(),
            IconButton(
              tooltip: 'Services (vélo, recharge, eau)',
              onPressed: onServices,
              isSelected: services,
              icon: const Icon(Icons.pedal_bike_outlined),
              selectedIcon: const Icon(Icons.pedal_bike, color: Color(0xFF3949AB)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 8,
      endIndent: 8,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

// Marqueur "épingle" pour les signalements (bulle colorée + pointe).
class _Pin extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool faded;
  final VoidCallback? onTap;
  const _Pin({required this.icon, required this.color, this.faded = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: faded ? 0.45 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            Transform.translate(
              offset: const Offset(0, -3),
              child: Transform.rotate(
                angle: 0.785398, // 45°
                child: Container(
                  width: 10,
                  height: 10,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Petite pastille ronde (espaces verts, services).
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
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
        ),
        child: Icon(icon, color: color, size: small ? 16 : 20),
      ),
    );
  }
}

// Point bleu "ma position".
class _MyLocationDot extends StatelessWidget {
  const _MyLocationDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A73E8),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
      ),
    );
  }
}

// Feuille pour créer un nouveau signalement.
class FeuilleAjout extends StatefulWidget {
  final LatLng position;
  const FeuilleAjout({super.key, required this.position});

  @override
  State<FeuilleAjout> createState() => _FeuilleAjoutState();
}

class _FeuilleAjoutState extends State<FeuilleAjout> {
  TypeDanger type = TypeDanger.trottoir;
  final description = TextEditingController();
  final pseudo = TextEditingController();

  @override
  void dispose() {
    description.dispose();
    pseudo.dispose();
    super.dispose();
  }

  void _envoyer() {
    if (description.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Décris le danger avant d\'envoyer.'),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      Signalement(
        type: type,
        position: widget.position,
        description: description.text.trim(),
        auteur: pseudo.text.trim().isEmpty ? 'Anonyme' : pseudo.text.trim(),
        date: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Signaler un danger',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Aide ta ville à rester sûre et agréable.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 18),
          const Text('Type', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in TypeDanger.values)
                ChoiceChip(
                  avatar: Icon(
                    iconDanger(t),
                    size: 18,
                    color: t == type ? Colors.white : couleurDanger(t),
                  ),
                  label: Text(labelDanger(t)),
                  selected: t == type,
                  selectedColor: couleurDanger(t),
                  labelStyle: TextStyle(
                    color: t == type ? Colors.white : null,
                    fontWeight: FontWeight.w500,
                  ),
                  onSelected: (_) => setState(() => type = t),
                ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: description,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'Décris ce que tu as vu...',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: pseudo,
            decoration: const InputDecoration(
              labelText: 'Pseudo (optionnel)',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _envoyer,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            icon: const Icon(Icons.send),
            label: const Text('Envoyer le signalement'),
          ),
        ],
      ),
    );
  }
}

// Feuille de détail d'un signalement, avec les commentaires et le ratio.
class FeuilleDetail extends StatefulWidget {
  final Signalement signalement;
  final VoidCallback onMaj;
  const FeuilleDetail({super.key, required this.signalement, required this.onMaj});

  @override
  State<FeuilleDetail> createState() => _FeuilleDetailState();
}

class _FeuilleDetailState extends State<FeuilleDetail> {
  final commentaire = TextEditingController();

  Signalement get s => widget.signalement;

  @override
  void dispose() {
    commentaire.dispose();
    super.dispose();
  }

  // Met à jour l'affichage ici ET sur la carte derrière.
  void _maj(VoidCallback action) {
    setState(action);
    widget.onMaj();
  }

  void _voter() {
    _maj(() {
      s.jaiVote = !s.jaiVote;
      s.votes += s.jaiVote ? 1 : -1;
      if (s.votes < 0) s.votes = 0;
    });
  }

  void _aimer(Commentaire c) {
    _maj(() {
      c.jaime = !c.jaime;
      c.likes += c.jaime ? 1 : -1;
      if (c.likes < 0) c.likes = 0;
    });
  }

  void _commenter() {
    final texte = commentaire.text.trim();
    if (texte.isEmpty) return;
    _maj(() => s.commentaires.add(Commentaire('Moi', texte)));
    commentaire.clear();
  }

  Future<void> _repondre(Commentaire parent) async {
    final champ = TextEditingController();
    final texte = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Répondre'),
        content: TextField(
          controller: champ,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Ta réponse...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, champ.text.trim()),
            child: const Text('Répondre'),
          ),
        ],
      ),
    );
    if (texte != null && texte.isNotEmpty) {
      _maj(() => parent.reponses.add(Commentaire('Moi', texte)));
    }
  }

  String _ilYa(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    return 'il y a ${diff.inDays} j';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: couleurDanger(s.type).withValues(alpha: 0.15),
                  child: Icon(iconDanger(s.type), color: couleurDanger(s.type)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(labelDanger(s.type),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('Par ${s.auteur} · ${_ilYa(s.date)}',
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                    ],
                  ),
                ),
                if (s.resolu)
                  Chip(
                    avatar: const Icon(Icons.check, size: 16, color: Color(0xFF2E7D32)),
                    label: const Text('Résolu'),
                    backgroundColor: const Color(0xFFE6F4EA),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(s.description, style: const TextStyle(fontSize: 15, height: 1.4)),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _voter,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: s.jaiVote ? cs.primary : null,
                  ),
                  icon: Icon(
                    s.jaiVote ? Icons.thumb_up : Icons.thumb_up_alt_outlined,
                    size: 18,
                  ),
                  label: Text('${s.votes}'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _maj(() => s.resolu = !s.resolu),
                  icon: Icon(s.resolu ? Icons.undo : Icons.check_circle_outline, size: 18),
                  label: Text(s.resolu ? 'Rouvrir' : 'Marquer résolu'),
                ),
              ],
            ),
            const Divider(height: 28),
            Text('Commentaires (${s.commentaires.length})',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (s.commentaires.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Sois le premier à commenter.',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            for (final c in s.commentaires) _tuileCommentaire(c),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: commentaire,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Ajouter un commentaire...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _commenter(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _commenter,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tuileCommentaire(Commentaire c) {
    final cs = Theme.of(context).colorScheme;
    final archive = c.estRatio;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (archive)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: const [
                  Icon(Icons.bolt, size: 16, color: Colors.deepOrange),
                  SizedBox(width: 4),
                  Text('Ratio : commentaire archivé',
                      style: TextStyle(
                          fontSize: 12, color: Colors.deepOrange, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          Opacity(
            opacity: archive ? 0.5 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.auteur, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  c.texte,
                  style: TextStyle(
                    decoration: archive ? TextDecoration.lineThrough : null,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _aimer(c),
                icon: Icon(c.jaime ? Icons.favorite : Icons.favorite_border,
                    size: 16, color: c.jaime ? Colors.red : null),
                label: Text('${c.likes}'),
              ),
              TextButton.icon(
                onPressed: () => _repondre(c),
                icon: const Icon(Icons.reply, size: 16),
                label: const Text('Répondre'),
              ),
            ],
          ),
          for (final r in c.reponses)
            Container(
              margin: const EdgeInsets.only(left: 16, top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
                border: r.likes > c.likes
                    ? Border.all(color: Colors.deepOrange, width: 1.5)
                    : Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.auteur,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(r.texte, style: const TextStyle(fontSize: 13)),
                  TextButton.icon(
                    onPressed: () => _aimer(r),
                    icon: Icon(r.jaime ? Icons.favorite : Icons.favorite_border,
                        size: 14, color: r.jaime ? Colors.red : null),
                    label: Text('${r.likes}', style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
