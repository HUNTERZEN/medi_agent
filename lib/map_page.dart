import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:http/http.dart' as http;

class HospitalMapPage extends StatefulWidget {
  final bool isDark;
  const HospitalMapPage({super.key, required this.isDark});

  @override
  State<HospitalMapPage> createState() => _HospitalMapPageState();
}

class _HospitalMapPageState extends State<HospitalMapPage> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  final Set<Marker> _markers = {};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Location services are disabled. Please enable them in settings.";
        });
        return;
      }

      // Check for permissions
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

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Location permissions are permanently denied.";
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      
      if (!mounted) return;

      setState(() {
        _currentPosition = position;
        _errorMessage = null;
      });
      
      _fetchNearbyHospitals(position);
    } catch (e) {
      debugPrint("Error initializing location: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Could not determine your location. Please try again.";
        });
      }
    }
  }

  Future<void> _fetchNearbyHospitals(Position pos) async {
    setState(() => _isLoading = true);
    
    // Using 10km radius
    final String query = """
    [out:json];
    (
      node["amenity"="hospital"](around:10000, ${pos.latitude}, ${pos.longitude});
      way["amenity"="hospital"](around:10000, ${pos.latitude}, ${pos.longitude});
      relation["amenity"="hospital"](around:10000, ${pos.latitude}, ${pos.longitude});
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

        setState(() {
          _markers.clear();
          // Add current location marker (Azure blue)
          _markers.add(
            Marker(
              markerId: const MarkerId("current_pos"),
              position: LatLng(pos.latitude, pos.longitude),
              infoWindow: const InfoWindow(title: "Your Location"),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            ),
          );

          for (var element in elements) {
            double lat = element['lat'] ?? element['center']['lat'];
            double lon = element['lon'] ?? element['center']['lon'];
            String name = element['tags']['name'] ?? "Hospital";

            _markers.add(
              Marker(
                markerId: MarkerId(element['id'].toString()),
                position: LatLng(lat, lon),
                infoWindow: InfoWindow(
                  title: name,
                  snippet: "Nearest Hospital",
                ),
              ),
            );
          }
          _isLoading = false;
        });
        
        if (elements.isEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No hospitals found within 10km.")),
          );
        } else {
          _fitMarkers();
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Error fetching hospitals: $e");
      if (mounted) setState(() => _isLoading = false);
    }
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
        LatLngBounds(
          southwest: LatLng(minLat, minLon),
          northeast: LatLng(maxLat, maxLon),
        ),
        70.0, // Padding
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: AppBar(
              backgroundColor: widget.isDark ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.4),
              elevation: 0,
              leading: Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded, color: widget.isDark ? Colors.white : Colors.black87),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              title: Text(
                "Nearest Hospitals",
                style: TextStyle(
                  color: widget.isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  letterSpacing: -0.5,
                ),
              ),
              centerTitle: true,
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _currentPosition == null) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF007AFF)));
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off_rounded, size: 64, color: widget.isDark ? Colors.white24 : Colors.black12),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: widget.isDark ? Colors.white70 : Colors.black54, fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _initLocation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF007AFF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Retry", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
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
          mapType: MapType.normal,
          style: widget.isDark ? _darkMapStyle : null,
        ),
        
        // Floating Action Buttons
        Positioned(
          bottom: 30,
          right: 20,
          child: Column(
            children: [
              _mapActionButton(
                icon: Icons.my_location_rounded,
                onTap: () {
                  if (_currentPosition != null) {
                    _mapController?.animateCamera(
                      CameraUpdate.newLatLng(
                        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 12),
              _mapActionButton(
                icon: Icons.refresh_rounded,
                onTap: () => _initLocation(),
              ),
            ],
          ),
        ),

        if (_isLoading)
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    color: widget.isDark ? Colors.black.withOpacity(0.5) : Colors.white.withOpacity(0.5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Text("Searching...", style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _mapActionButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: widget.isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
              ),
            ),
            child: Icon(icon, color: widget.isDark ? Colors.white : Colors.black87, size: 24),
          ),
        ),
      ),
    );
  }

  // Dark Map Style (Standard Google Maps Dark JSON)
  final String _darkMapStyle = """
[
  {
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#242f3e"
      }
    ]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#746855"
      }
    ]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [
      {
        "color": "#242f3e"
      }
    ]
  },
  {
    "featureType": "administrative.locality",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#d59563"
      }
    ]
  },
  {
    "featureType": "poi",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#d59563"
      }
    ]
  },
  {
    "featureType": "poi.park",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#263c3f"
      }
    ]
  },
  {
    "featureType": "poi.park",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#6b9a76"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#38414e"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "geometry.stroke",
    "stylers": [
      {
        "color": "#212a37"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#9ca5b3"
      }
    ]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#746855"
      }
    ]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry.stroke",
    "stylers": [
      {
        "color": "#1f2835"
      }
    ]
  },
  {
    "featureType": "road.highway",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#f3d19c"
      }
    ]
  },
  {
    "featureType": "transit",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#2f3948"
      }
    ]
  },
  {
    "featureType": "transit.station",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#d59563"
      }
    ]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#17263c"
      }
    ]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#515c6d"
      }
    ]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.stroke",
    "stylers": [
      {
        "color": "#17263c"
      }
    ]
  }
]
""";
}
