import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Transvlles',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MapPage(),
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  LatLng? _myPosition; // null = pas encore localisé
  bool _loading = false;

  // Demande la permission et récupère la position
  Future<void> _goToMyLocation() async {
    setState(() => _loading = true);

    // Vérifie si le service GPS est activé
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Active le GPS sur ton téléphone.')),
      );
      return;
    }

    // Vérifie / demande la permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Permission refusée.')));
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permission bloquée. Va dans les paramètres.'),
        ),
      );
      return;
    }

    // Récupère la position
    Position pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _myPosition = LatLng(pos.latitude, pos.longitude);
      _loading = false;
    });

    // Centre la carte sur ta position
    _mapController.move(_myPosition!, 15.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(50.6292, 3.0573), // Lille
              initialZoom: 13.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.transvlles',
              ),
              // Affiche un marqueur bleu sur ta position
              if (_myPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _myPosition!,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.blue,
                        size: 40,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Bouton "Ma position" en haut à droite
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: FloatingActionButton(
              mini: true,
              onPressed: _loading ? null : _goToMyLocation,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),

          // Barre de recherche + boutons en bas
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SearchAnchor(
                  isFullScreen: false,
                  viewConstraints: const BoxConstraints(maxHeight: 300),
                  builder: (BuildContext context, SearchController controller) {
                    return SearchBar(
                      controller: controller,
                      padding: const WidgetStatePropertyAll<EdgeInsets>(
                        EdgeInsets.symmetric(horizontal: 16.0),
                      ),
                      hintText: 'Rechercher une ligne...',
                      onTap: () => controller.openView(),
                      onChanged: (_) => controller.openView(),
                      leading: const Icon(Icons.search),
                    );
                  },
                  suggestionsBuilder:
                      (BuildContext context, SearchController controller) {
                        final suggestions = [
                          'Ligne 1 - Métro',
                          'Ligne 2 - Métro',
                          'Bus 67',
                          'Bus 12',
                        ];
                        final query = controller.text.toLowerCase();
                        final filtered = suggestions
                            .where((s) => s.toLowerCase().contains(query))
                            .toList();
                        return filtered.map((item) {
                          return ListTile(
                            leading: const Icon(Icons.directions_bus),
                            title: Text(item),
                            onTap: () {
                              setState(() => controller.closeView(item));
                            },
                          );
                        }).toList();
                      },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.schedule),
                        label: const Text('Horaires'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.warning_rounded),
                        label: const Text('Signalements'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
