import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:transvlles/models/gtfs_models.dart';
import 'package:transvlles/services/db_helper.dart';
import 'package:transvlles/services/signalement_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Écran principal du module "Transports".
class AfficherLigne extends StatefulWidget {
  final String? rechercheInitiale;

  const AfficherLigne({super.key, this.rechercheInitiale});

  @override
  State<AfficherLigne> createState() => _AfficherLigneState();
}

class _AfficherLigneState extends State<AfficherLigne> {
  late final TextEditingController _searchController;
  
  String _currentFilter = 'Lignes'; 
  String _searchQuery = "";
  List<String> _pinnedStops = [];

  @override
  void initState() {
    super.initState();
    _searchQuery = widget.rechercheInitiale ?? "";
    _searchController = TextEditingController(text: _searchQuery);
    _loadFavorites();
  }

  /// Charge la liste des identifiants d'arrêts favoris depuis le stockage local.
  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _pinnedStops = prefs.getStringList('fav_stops') ?? [];
    });
  }

  /// Ajoute ou retire un arrêt de la liste des favoris et met à jour le stockage local.
  Future<void> _toggleFavorite(String stopId) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_pinnedStops.contains(stopId)) {
        _pinnedStops.remove(stopId);
      } else {
        _pinnedStops.add(stopId);
      }
    });
    await prefs.setStringList('fav_stops', _pinnedStops);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transvlles')),
      body: Column(
        children: [
          if (_currentFilter != 'Favoris')
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  labelText: 'Chercher...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.0)),
                ),
              ),
            ),
          
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _getFutureData(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Text(_currentFilter == 'Favoris' ? "Aucun favori pour le moment" : "Aucun résultat")
                  );
                }

                if (_currentFilter == 'Lignes') {
                  return _buildLinesGrid(snapshot.data!.cast<Ligne>());
                } else {
                  return _buildStopsList(snapshot.data!.cast<Arret>());
                }
              },
            ),
          ),
          _buildBottomNav(),
        ],
      ),
    );
  }

  /// Routeur de données selon le filtre actif.
  Future<List<dynamic>> _getFutureData() {
    if (_currentFilter == 'Lignes') return DBHelper().getRoutes(_searchQuery);
    if (_currentFilter == 'Arrêts') return DBHelper().getStops(_searchQuery);
    return DBHelper().getStopsByIds(_pinnedStops); 
  }

  /// Construit la barre de navigation inférieure.
  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _currentFilter == 'Lignes' ? 0 : (_currentFilter == 'Arrêts' ? 1 : 2),
      selectedItemColor: Colors.pink,
      unselectedItemColor: Colors.grey,
      onTap: (index) {
        setState(() {
          if (index == 0) {
            _currentFilter = 'Lignes';
          } else if (index == 1) { 
            _currentFilter = 'Arrêts';
          } else { 
            _currentFilter = 'Favoris';
          }
          _searchController.clear();
          _searchQuery = "";
        });
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.directions_bus), label: 'Lignes'),
        BottomNavigationBarItem(icon: Icon(Icons.place), label: 'Arrêts'),
        BottomNavigationBarItem(icon: Icon(Icons.star), label: 'Favoris'),
      ],
    );
  }

  /// Affiche une grille visuelle représentant les lignes de transport.
  Widget _buildLinesGrid(List<Ligne> lignes) {
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4),
      itemCount: lignes.length,
      itemBuilder: (context, index) {
        final ligne = lignes[index];
        return Card(
          color: ligne.color,
          child: InkWell(
            onTap: () => _showStopsForRoute(ligne),
            child: Center(
              child: Text(
                ligne.shortName, 
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
              )
            ),
          ),
        );
      },
    );
  }

  /// Affiche la liste des arrêts sous forme de liste défilante.
  Widget _buildStopsList(List<Arret> arrets) {
    return ListView.separated(
      itemCount: arrets.length,
      separatorBuilder: (context, index) => const Divider(color: Colors.white10),
      itemBuilder: (context, index) {
        final arret = arrets[index];
        final isFav = _pinnedStops.contains(arret.id);
        return ListTile(
          leading: Icon(
            isFav ? Icons.star : Icons.location_on, 
            color: isFav ? Colors.yellow : Colors.grey
          ),
          title: Text(arret.name),
          onTap: () => _showRoutesForStop(arret),
        );
      },
    );
  }

  /// Affiche une fenêtre modale détaillant les horaires et les signalements communautaires.
  void _showHorairesPopUp(BuildContext context, String stopId, String stopName, String routeId) {
    bool showOnlyFuture = true; 

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: FutureBuilder<Map<String, dynamic>>(
              future: Future.wait([
                DBHelper().getStopTimes(stopId, routeId),
                SignalementService().getMoyenneRetard(stopId, routeId),
                SignalementService().aUneAlerteControleur(stopId),
              ]).then((results) => {
                'horaires': results[0],
                'retard': results[1],
                'controleur': results[2],
              }),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.pink));
                }
                
                final data = snapshot.data!['horaires'] as Map<String, dynamic>;
                final int avgDelay = snapshot.data!['retard'] as int;
                final bool alerteControleur = snapshot.data!['controleur'] as bool;

                final now = TimeOfDay.now();
                final String currentTime = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

                List<Map<String, String>> filterTimes(dynamic passages) {
                  List<Map<String, String>> list = List<Map<String, String>>.from(passages);
                  if (!showOnlyFuture) return list;
                  return list.where((t) => t["time"]!.compareTo(currentTime) >= 0).toList();
                }

                return DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(10))),
                      
                      if (alerteControleur)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.all(10),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.blueAccent, borderRadius: BorderRadius.circular(10)),
                          child: const Center(child: Text("👮‍♂️ CONTRÔLEURS SIGNALÉS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                        ),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        child: Row(
                          children: [
                            Expanded(child: Text(stopName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.pink))),
                            IconButton(
                              icon: Icon(_pinnedStops.contains(stopId) ? Icons.star : Icons.star_border, color: Colors.yellow),
                              onPressed: () async {
                                await _toggleFavorite(stopId);
                                setModalState(() {}); 
                              },
                            )
                          ],
                        ),
                      ),

                      _buildSignalementBar(stopId, stopName, routeId),

                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _filterButton("Prochains", showOnlyFuture, () => setModalState(() => showOnlyFuture = true)),
                            const SizedBox(width: 10),
                            _filterButton("Tous", !showOnlyFuture, () => setModalState(() => showOnlyFuture = false)),
                          ],
                        ),
                      ),

                      TabBar(
                        indicatorColor: Colors.pink,
                        labelColor: Colors.pink,
                        tabs: [
                          Tab(text: data["TerminusAller"] ?? "Aller"),
                          Tab(text: data["TerminusRetour"] ?? "Retour"),
                        ],
                      ),

                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildTimetable(filterTimes(data["Aller"]), avgDelay),
                            _buildTimetable(filterTimes(data["Retour"]), avgDelay),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        }
      ),
    );
  }

  /// Construit la liste déroulante des horaires pour une direction donnée.
  Widget _buildTimetable(List<Map<String, String>> passages, int delay) {
    if (passages.isEmpty) return const Center(child: Text("Aucun bus", style: TextStyle(color: Colors.grey)));
    
    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: passages.length,
      itemBuilder: (context, i) {
        return ListTile(
          leading: Text(passages[i]["time"]!, style: const TextStyle(color: Colors.pink, fontWeight: FontWeight.bold, fontSize: 16)),
          title: Text(passages[i]["dest"]!, style: const TextStyle(color: Colors.white)),
          subtitle: delay > 0 ? Text("Retard habituel: +$delay min", style: const TextStyle(color: Colors.orange)) : null,
        );
      },
    );
  }

  /// Construit un bouton de filtre standardisé pour l'interface utilisateur.
  Widget _filterButton(String label, bool isActive, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(backgroundColor: isActive ? Colors.pink : Colors.grey[800]),
      child: Text(label, style: const TextStyle(color: Colors.white)),
    );
  }

  /// Construit la barre d'outils permettant la création de signalements communautaires.
  Widget _buildSignalementBar(String stopId, String stopName, String routeId) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _sigBtn(Icons.policy, "Police", Colors.blue, "controleur", stopId, stopName, routeId),
        _sigBtn(Icons.warning, "Retard", Colors.orange, "retard", stopId, stopName, routeId),
        _sigBtn(Icons.sentiment_satisfied, "Ok", Colors.green, "satisfait", stopId, stopName, routeId),
      ],
    );
  }

  /// Construit un bouton individuel de signalement.
  Widget _sigBtn(IconData icon, String label, Color col, String type, String sId, String sName, String rId) {
    return Column(
      children: [
        IconButton(icon: Icon(icon, color: col), onPressed: () => _envoyerSig(type, sId, sName, rId)),
        Text(label, style: TextStyle(color: col, fontSize: 10)),
      ],
    );
  }

  /// Exécute la logique d'envoi d'un signalement vers la base de données cloud (Firestore).
  void _envoyerSig(String type, String sId, String sName, String rId) async {
    debugPrint("Envoi de signalement : [$type] pour l'arrêt [$sName]"); 
    
    try {
      await SignalementService().envoyerSignalement(
        type: type, 
        stopId: sId, 
        stopName: sName, 
        routeId: rId, 
        valeur: type == "retard" ? 5 : 0
      );
      debugPrint("Signalement transmis avec succès."); 
    } catch (e) {
      debugPrint("Erreur lors de la transmission Firestore : $e"); 
    }
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Signalement $type envoyé !")));
  }

  /// Ouvre une modale listant tous les arrêts desservis par une ligne spécifique.
  void _showStopsForRoute(Ligne ligne) async {
    final arrets = await DBHelper().getStopsForRoute(ligne.id);
    if (!mounted) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => ListView.builder(
        itemCount: arrets.length,
        itemBuilder: (context, i) => ListTile(
          title: Text(arrets[i].name, style: const TextStyle(color: Colors.white)),
          onTap: () { 
            Navigator.pop(context); 
            _showHorairesPopUp(context, arrets[i].id, arrets[i].name, ligne.id); 
          },
        ),
      ),
    );
  }

  /// Ouvre une modale listant toutes les lignes desservant un arrêt spécifique.
  void _showRoutesForStop(Arret arret) async {
    final lignes = await DBHelper().getRoutesForStop(arret.id);
    if (!mounted) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => ListView.builder(
        itemCount: lignes.length,
        itemBuilder: (context, i) => ListTile(
          leading: CircleAvatar(backgroundColor: lignes[i].color, child: Text(lignes[i].shortName, style: const TextStyle(fontSize: 10))),
          title: Text(lignes[i].longName, style: const TextStyle(color: Colors.white)),
          onTap: () { 
            Navigator.pop(context); 
            _showHorairesPopUp(context, arret.id, arret.name, lignes[i].id); 
          },
        ),
      ),
    );
  }
}