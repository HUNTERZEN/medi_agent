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

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = position;
        _isLoading = false;
      });
      _fetchNearbyHospitals(position);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not get your location")),
        );
      }
    }
  }

  Future<void> _fetchNearbyHospitals(Position pos) async {
    // We'll use the Overpass API (OpenStreetMap) to find hospitals
    // This doesn't require an API key and is free to use.
    final String query = """
    [out:json];
    (
      node["amenity"="hospital"](around:5000, ${pos.latitude}, ${pos.longitude});
      way["amenity"="hospital"](around:5000, ${pos.latitude}, ${pos.longitude});
      relation["amenity"="hospital"](around:5000, ${pos.latitude}, ${pos.longitude});
    );
    out center;
    """;

    final url = Uri.parse("https://overpass-api.de/api/interpreter?data=${Uri.encodeComponent(query)}");

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List elements = data['elements'];

        setState(() {
          _markers.clear();
          // Add current location marker
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
        });
      }
    } catch (e) {
      debugPrint("Error fetching hospitals: $e");
    }
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
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: const Color(0xFF007AFF),
              ),
            )
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                    zoom: 14,
                  ),
                  onMapCreated: (controller) => _mapController = controller,
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
                          _mapController?.animateCamera(
                            CameraUpdate.newLatLng(
                              LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _mapActionButton(
                        icon: Icons.refresh_rounded,
                        onTap: () => _fetchNearbyHospitals(_currentPosition!),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
