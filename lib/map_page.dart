import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class HospitalMapPage extends StatefulWidget {
  final bool isDark;
  const HospitalMapPage({super.key, required this.isDark});

  @override
  State<HospitalMapPage> createState() => _HospitalMapPageState();
}

class _HospitalMapPageState extends State<HospitalMapPage> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  Set<Marker> _markers = {};
  List<Map<String, dynamic>> _hospitals = [];
  bool _isLoading = true;
  String? _errorMessage = null;
  final TextEditingController _searchController = TextEditingController();
  
  // Tab/Panel state
  bool _isPanelOpen = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Location services are disabled.";
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _isLoading = false;
            _errorMessage = "Location permissions are denied.";
          });
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      
      if (!mounted) return;

      setState(() {
        _currentPosition = position;
        _errorMessage = null;
      });
      
      _fetchNearbyHospitals(position.latitude, position.longitude);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Could not determine location.";
        });
      }
    }
  }

  Future<void> _fetchNearbyHospitals(double lat, double lon, {String? searchQuery}) async {
    setState(() => _isLoading = true);
    
    String filter = '["amenity"~"hospital|clinic"]';
    if (searchQuery != null && searchQuery.isNotEmpty) {
      filter += '["name"~"$searchQuery",i]';
    }

    final String query = """
    [out:json];
    (
      node$filter(around:10000, $lat, $lon);
      way$filter(around:10000, $lat, $lon);
      relation$filter(around:10000, $lat, $lon);
    );
    out center;
    """;

    final url = Uri.parse("https://overpass-api.de/api/interpreter?data=${Uri.encodeComponent(query)}");

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List elements = data['elements'];

        if (!mounted) return;

        List<Map<String, dynamic>> tempHospitals = [];
        Set<Marker> tempMarkers = {
          Marker(
            markerId: const MarkerId("current_pos"),
            position: LatLng(lat, lon),
            infoWindow: const InfoWindow(title: "Your Location"),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          ),
        };

        for (var element in elements) {
          double hLat = element['lat'] ?? element['center']['lat'];
          double hLon = element['lon'] ?? element['center']['lon'];
          String name = element['tags']['name'] ?? "Medical Center";
          String type = element['tags']['amenity'] ?? "hospital";
          String address = element['tags']['addr:street'] ?? "Nearby";

          double distance = Geolocator.distanceBetween(lat, lon, hLat, hLon) / 1000;

          tempHospitals.add({
            'name': name,
            'type': type,
            'lat': hLat,
            'lon': hLon,
            'distance': distance,
            'address': address,
          });

          tempMarkers.add(
            Marker(
              markerId: MarkerId(element['id'].toString()),
              position: LatLng(hLat, hLon),
              infoWindow: InfoWindow(title: name, snippet: "${distance.toStringAsFixed(1)} km away"),
              onTap: () => _focusHospital(hLat, hLon),
            ),
          );
        }

        tempHospitals.sort((a, b) => a['distance'].compareTo(b['distance']));

        setState(() {
          _hospitals = tempHospitals;
          _markers = tempMarkers;
          _isLoading = false;
        });
        
        if (_hospitals.isNotEmpty) _fitMarkers();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _focusHospital(double lat, double lon) {
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lon), 15));
  }

  void _fitMarkers() {
    if (_markers.isEmpty || _mapController == null) return;
    double minLat = _markers.first.position.latitude;
    double maxLat = _markers.first.position.latitude;
    double minLon = _markers.first.position.longitude;
    double maxLon = _markers.first.position.longitude;

    for (var m in _markers) {
      if (m.position.latitude < minLat) minLat = m.position.latitude;
      if (m.position.latitude > maxLat) maxLat = m.position.latitude;
      if (m.position.longitude < minLon) minLon = m.position.longitude;
      if (m.position.longitude > maxLon) maxLon = m.position.longitude;
    }

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(minLat, minLon), northeast: LatLng(maxLat, maxLon)),
        70.0,
      ),
    );
  }

  Future<void> _openDirections(double lat, double lon) async {
    final urlString = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=driving';
    final url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(_currentPosition?.latitude ?? 0, _currentPosition?.longitude ?? 0),
              zoom: 14,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              if (_markers.isNotEmpty) _fitMarkers();
            },
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            style: widget.isDark ? _darkMapStyle : null,
          ),

          // Search Bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                children: [
                  _frostedSearch(),
                ],
              ),
            ),
          ),

          // Mini Tab / Box at the bottom
          _buildMiniTab(),

          // Loading Indicator
          if (_isLoading)
            Positioned(
              top: 150,
              left: 0,
              right: 0,
              child: Center(child: _frostedLoading()),
            ),
        ],
      ),
    );
  }

  Widget _frostedSearch() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: widget.isDark ? Colors.black.withOpacity(0.4) : Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: widget.isDark ? Colors.white10 : Colors.black12),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: widget.isDark ? Colors.white : Colors.black87, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: "Search hospitals or clinics...",
                    hintStyle: TextStyle(color: widget.isDark ? Colors.white38 : Colors.black38),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (val) {
                    if (_currentPosition != null) {
                      _fetchNearbyHospitals(_currentPosition!.latitude, _currentPosition!.longitude, searchQuery: val);
                    }
                  },
                ),
              ),
              IconButton(
                icon: Icon(Icons.search_rounded, color: widget.isDark ? Colors.white70 : Colors.black54),
                onPressed: () {
                  if (_currentPosition != null) {
                    _fetchNearbyHospitals(_currentPosition!.latitude, _currentPosition!.longitude, searchQuery: _searchController.text);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniTab() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
      bottom: 20,
      left: 16,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The Mini Tab Header
          GestureDetector(
            onTap: () => setState(() => _isPanelOpen = !_isPanelOpen),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: widget.isDark ? const Color(0xFF1A1A2E).withOpacity(0.8) : Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: widget.isDark ? Colors.white10 : Colors.black12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.local_hospital_rounded, color: const Color(0xFF007AFF), size: 22),
                      const SizedBox(width: 12),
                      Text(
                        "Nearby Centers",
                        style: TextStyle(fontWeight: FontWeight.bold, color: widget.isDark ? Colors.white : Colors.black87),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          "${_hospitals.length}",
                          style: const TextStyle(color: Color(0xFF007AFF), fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _isPanelOpen ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                        color: Colors.grey,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // The Expandable List Content
          if (_isPanelOpen) ...[
            const SizedBox(height: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 280, // Fixed height for the "box"
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: widget.isDark ? const Color(0xFF1A1A2E).withOpacity(0.7) : Colors.white.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: widget.isDark ? Colors.white10 : Colors.black12),
                    ),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: _hospitals.length,
                      itemBuilder: (context, index) {
                        final h = _hospitals[index];
                        return _hospitalTile(h);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _hospitalTile(Map<String, dynamic> h) {
    return GestureDetector(
      onTap: () => _focusHospital(h['lat'], h['lon']),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: widget.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              h['type'] == 'hospital' ? Icons.local_hospital_rounded : Icons.medical_services_rounded,
              color: const Color(0xFF007AFF),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    h['name'],
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: widget.isDark ? Colors.white : Colors.black87),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    "${h['distance'].toStringAsFixed(1)} km · ${h['address']}",
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.directions_rounded, color: Color(0xFF30D158), size: 22),
              onPressed: () => _openDirections(h['lat'], h['lon']),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frostedLoading() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: widget.isDark ? Colors.black.withOpacity(0.5) : Colors.white.withOpacity(0.5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF007AFF))),
              const SizedBox(width: 12),
              Text("Finding centers...", style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87)),
            ],
          ),
        ),
      ),
    );
  }

  final String _darkMapStyle = """
[
  {"elementType": "geometry", "stylers": [{"color": "#242f3e"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#746855"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#242f3e"}]},
  {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#d59563"}]},
  {"featureType": "poi", "elementType": "labels.text.fill", "stylers": [{"color": "#d59563"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#263c3f"}]},
  {"featureType": "poi.park", "elementType": "labels.text.fill", "stylers": [{"color": "#6b9a76"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#38414e"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#212a37"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#9ca5b3"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#746855"}]},
  {"featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{"color": "#1f2835"}]},
  {"featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{"color": "#f3d19c"}]},
  {"featureType": "transit", "elementType": "geometry", "stylers": [{"color": "#2f3948"}]},
  {"featureType": "transit.station", "elementType": "labels.text.fill", "stylers": [{"color": "#d59563"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#17263c"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#515c6d"}]},
  {"featureType": "water", "elementType": "labels.text.stroke", "stylers": [{"color": "#17263c"}]}
]
""";
}
