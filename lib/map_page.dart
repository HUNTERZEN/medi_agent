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
  String? _errorMessage;
  final TextEditingController _searchController = TextEditingController();
  bool _isPanelOpen = false;

  Map<String, dynamic>? _selectedHospital;
  Set<Polyline> _polylines = {};
  String _travelMode = 'driving'; // 'driving', 'foot', 'bicycle'
  String? _routeDuration;
  String? _routeDistance;
  bool _isRouteLoading = false;

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
      
      // Fetch hospitals after getting position
      _fetchNearbyHospitals(position.latitude, position.longitude);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Could not determine your location.";
        });
      }
    }
  }

  Future<void> _fetchNearbyHospitals(double lat, double lon, {String? searchQuery}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    String nameFilter = "";
    if (searchQuery != null && searchQuery.isNotEmpty) {
      // Use case-insensitive regex for broader matching
      nameFilter = '["name"~"$searchQuery",i]';
    }

    final String query = """
    [out:json][timeout:60];
    (
      node["amenity"~"hospital|clinic|doctors|dentist|pharmacy"]$nameFilter(around:60000, $lat, $lon);
      node["healthcare"~"hospital|clinic|doctor|dentist|pharmacy"]$nameFilter(around:60000, $lat, $lon);
      way["amenity"~"hospital|clinic|doctors|dentist|pharmacy"]$nameFilter(around:60000, $lat, $lon);
      way["healthcare"~"hospital|clinic|doctor|dentist|pharmacy"]$nameFilter(around:60000, $lat, $lon);
      relation["amenity"~"hospital|clinic|doctors|dentist|pharmacy"]$nameFilter(around:60000, $lat, $lon);
      relation["healthcare"~"hospital|clinic|doctor|dentist|pharmacy"]$nameFilter(around:60000, $lat, $lon);
    );
    out center;
    """;

    // List of reliable worldwide Overpass API mirrors
    final List<String> mirrors = [
      "https://overpass-api.de/api/interpreter",
      "https://lz4.overpass-api.de/api/interpreter",
      "https://z.overpass-api.de/api/interpreter",
      "https://overpass.kumi.systems/api/interpreter",
    ];

    bool success = false;
    
    for (String baseUrl in mirrors) {
      if (success) break;
      
      try {
        debugPrint("Trying Overpass mirror: $baseUrl");
        final url = Uri.parse("$baseUrl?data=${Uri.encodeComponent(query)}");
        final response = await http.get(
          url,
          headers: {
            'User-Agent': 'MediAgentApp/1.0 (contact: support@mediagent.com)',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 25));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List elements = data['elements'] ?? [];

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
            try {
              double hLat = element['lat'] ?? element['center']['lat'];
              double hLon = element['lon'] ?? element['center']['lon'];
              Map<String, dynamic> tags = element['tags'] ?? {};
              String name = tags['name'] ?? tags['operator'] ?? "Medical Center";
              String type = tags['amenity'] ?? tags['healthcare'] ?? "hospital";
              String street = tags['addr:street'] ?? "";
              String city = tags['addr:city'] ?? "";
              String address = street.isNotEmpty ? "$street, $city" : "Nearby Facility";

              double distance = Geolocator.distanceBetween(lat, lon, hLat, hLon) / 1000;

              final Map<String, dynamic> hospitalItem = {
                'name': name,
                'type': type,
                'lat': hLat,
                'lon': hLon,
                'distance': distance,
                'address': address,
              };
              tempHospitals.add(hospitalItem);

              double markerHue = BitmapDescriptor.hueRed;
              if (type == 'pharmacy') {
                markerHue = BitmapDescriptor.hueGreen;
              } else if (type == 'clinic' || type == 'dentist' || type == 'doctors' || type == 'doctor') {
                markerHue = BitmapDescriptor.hueOrange;
              }

              tempMarkers.add(
                Marker(
                  markerId: MarkerId(element['id'].toString()),
                  position: LatLng(hLat, hLon),
                  icon: BitmapDescriptor.defaultMarkerWithHue(markerHue),
                  infoWindow: InfoWindow(title: name, snippet: "${distance.toStringAsFixed(1)} km away"),
                  onTap: () {
                    _selectHospital(hospitalItem);
                  },
                ),
              );
            } catch (e) {
              continue;
            }
          }

          tempHospitals.sort((a, b) => a['distance'].compareTo(b['distance']));

          setState(() {
            _hospitals = tempHospitals;
            _markers = tempMarkers;
            _isLoading = false;
          });
          
          if (_hospitals.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("No centers found for this search.")),
            );
          } else {
            _fitMarkers();
          }
          success = true;
          break;
        }
      } catch (e) {
        debugPrint("Mirror $baseUrl failed: $e");
        continue; // Try next mirror
      }
    }

    if (!success && mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Search service busy. Please try again in a few seconds."),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _fitMarkers() {
    if (_markers.isEmpty || _mapController == null) return;
    
    // If only current location marker is present, don't fit bounds
    if (_markers.length == 1) {
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_markers.first.position, 14));
      return;
    }

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
        80.0,
      ),
    );
  }

  Future<void> _openDirections(double lat, double lon) async {
    String googleTravelMode = 'driving';
    if (_travelMode == 'foot') {
      googleTravelMode = 'walking';
    } else if (_travelMode == 'bicycle') {
      googleTravelMode = 'bicycling';
    }

    final urlString = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=$googleTravelMode';
    final url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _selectHospital(Map<String, dynamic> h) {
    setState(() {
      _selectedHospital = h;
      _isPanelOpen = false; // collapse general list to show directions card
    });
    _fetchRoute(h['lat'], h['lon']);
  }

  Future<void> _fetchRoute(double destLat, double destLon) async {
    if (_currentPosition == null) return;
    
    setState(() {
      _isRouteLoading = true;
      _polylines.clear();
      _routeDuration = null;
      _routeDistance = null;
    });

    final double startLat = _currentPosition!.latitude;
    final double startLon = _currentPosition!.longitude;
    
    String osrmProfile = 'driving';
    if (_travelMode == 'foot') {
      osrmProfile = 'foot';
    } else if (_travelMode == 'bicycle') {
      osrmProfile = 'bicycle';
    }

    final String urlString = 'https://router.project-osrm.org/route/v1/$osrmProfile/$startLon,$startLat;$destLon,$destLat?overview=full&geometries=geojson';
    
    try {
      final response = await http.get(
        Uri.parse(urlString),
        headers: {
          'User-Agent': 'MediAgentApp/1.0 (contact: support@mediagent.com)',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry'];
          final List coordinates = geometry['coordinates'];
          
          final List<LatLng> polylinePoints = coordinates.map((coord) {
            double lon = coord[0] is int ? (coord[0] as int).toDouble() : coord[0];
            double lat = coord[1] is int ? (coord[1] as int).toDouble() : coord[1];
            return LatLng(lat, lon);
          }).toList();

          final double distanceInMeters = route['distance'] is int ? (route['distance'] as int).toDouble() : route['distance'];
          final double durationInSeconds = route['duration'] is int ? (route['duration'] as int).toDouble() : route['duration'];

          setState(() {
            _routeDistance = distanceInMeters >= 1000 
                ? "${(distanceInMeters / 1000).toStringAsFixed(1)} km"
                : "${distanceInMeters.toStringAsFixed(0)} m";
            
            final double minutes = durationInSeconds / 60;
            if (minutes >= 60) {
              final int hours = (minutes / 60).floor();
              final int remainingMins = (minutes % 60).round();
              _routeDuration = "${hours}h ${remainingMins}m";
            } else {
              _routeDuration = "${minutes.round()} min";
            }

            _polylines = {
              Polyline(
                polylineId: const PolylineId("route"),
                points: polylinePoints,
                color: const Color(0xFF007AFF),
                width: 5,
                jointType: JointType.round,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
              ),
            };
            _isRouteLoading = false;
          });

          _fitRoute(polylinePoints);
        } else {
          setState(() {
            _isRouteLoading = false;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("No route found for this travel mode.")),
            );
          });
        }
      } else {
        setState(() => _isRouteLoading = false);
      }
    } catch (e) {
      debugPrint("Error fetching route: $e");
      setState(() => _isRouteLoading = false);
    }
  }

  void _fitRoute(List<LatLng> points) {
    if (points.isEmpty || _mapController == null) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLon = points.first.longitude;
    double maxLon = points.first.longitude;

    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(minLat, minLon), northeast: LatLng(maxLat, maxLon)),
        90.0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: widget.isDark ? Colors.black : Colors.white,
      body: Stack(
        children: [
          // The Map Layer
          _currentPosition == null && _errorMessage == null
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF007AFF)))
              : GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(_currentPosition?.latitude ?? 0, _currentPosition?.longitude ?? 0),
                    zoom: 14,
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                    if (_markers.isNotEmpty) _fitMarkers();
                  },
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  compassEnabled: false,
                  mapToolbarEnabled: false,
                  style: widget.isDark ? _darkMapStyle : null,
                  onTap: (latLng) {
                    if (_selectedHospital != null) {
                      setState(() {
                        _selectedHospital = null;
                        _polylines.clear();
                      });
                    }
                  },
                ),

          // Search Overlay
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: _frostedSearch(),
            ),
          ),

          // Error Overlay
          if (_errorMessage != null)
            _buildErrorState(),

          // Mini Tab / Result Box
          if (_currentPosition != null && _errorMessage == null)
            _buildMiniTab(),

          // My Location Button
          if (_currentPosition != null)
            Positioned(
              right: 16,
              bottom: _selectedHospital != null 
                  ? 270 
                  : (_isPanelOpen ? 370 : 100),
              child: FloatingActionButton.small(
                onPressed: () {
                  if (_currentPosition != null) {
                    _mapController?.animateCamera(
                      CameraUpdate.newLatLngZoom(
                        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                        15,
                      ),
                    );
                  }
                },
                backgroundColor: widget.isDark ? const Color(0xFF1A1A2E) : Colors.white,
                foregroundColor: const Color(0xFF007AFF),
                child: const Icon(Icons.my_location_rounded),
              ),
            ),

          // Loading Overlay (Overlay during fetch)
          if (_isLoading && _currentPosition != null)
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

  Widget _buildErrorState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(30),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: widget.isDark ? Colors.black.withOpacity(0.8) : Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.red.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off_rounded, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _initLocation,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Try Again", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frostedSearch() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: widget.isDark ? Colors.black.withOpacity(0.4) : Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: widget.isDark ? Colors.white10 : Colors.black12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
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
                  style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: "Search medical centers...",
                    hintStyle: TextStyle(color: widget.isDark ? Colors.white38 : Colors.black38, fontSize: 15),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (val) => setState(() {}),
                  onSubmitted: (val) {
                    if (_currentPosition != null) {
                      _fetchNearbyHospitals(_currentPosition!.latitude, _currentPosition!.longitude, searchQuery: val);
                    }
                  },
                ),
              ),
              if (_searchController.text.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.close_rounded, color: widget.isDark ? Colors.white54 : Colors.black54, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                    if (_currentPosition != null) {
                      _fetchNearbyHospitals(_currentPosition!.latitude, _currentPosition!.longitude);
                    }
                  },
                ),
              Container(
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: IconButton(
                  icon: const Icon(Icons.search_rounded, color: Colors.white, size: 20),
                  onPressed: () {
                    if (_currentPosition != null) {
                      _fetchNearbyHospitals(_currentPosition!.latitude, _currentPosition!.longitude, searchQuery: _searchController.text);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTravelModeButton({
    required String mode,
    required IconData icon,
    required String tooltip,
  }) {
    final bool isSelected = _travelMode == mode;
    return GestureDetector(
      onTap: () {
        if (_selectedHospital == null || _isRouteLoading) return;
        setState(() {
          _travelMode = mode;
        });
        _fetchRoute(_selectedHospital!['lat'], _selectedHospital!['lon']);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF007AFF)
              : (widget.isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04)),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: isSelected
              ? Colors.white
              : (widget.isDark ? Colors.white70 : Colors.black54),
          size: 20,
        ),
      ),
    );
  }

  Widget _buildDirectionsCard() {
    if (_selectedHospital == null) return const SizedBox.shrink();
    
    final h = _selectedHospital!;
    final String name = h['name'];
    final String type = h['type'] ?? 'hospital';
    final String address = h['address'];

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF1A1A2E).withOpacity(0.85) : Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: widget.isDark ? Colors.white10 : Colors.black12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 25, offset: const Offset(0, -5)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      type == 'hospital' ? Icons.local_hospital_rounded : Icons.medical_services_rounded,
                      color: const Color(0xFF007AFF),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: widget.isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          address,
                          style: TextStyle(
                            color: widget.isDark ? Colors.white38 : Colors.black45,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: widget.isDark ? Colors.white54 : Colors.black54),
                    onPressed: () {
                      setState(() {
                        _selectedHospital = null;
                        _polylines.clear();
                      });
                    },
                  ),
                ],
              ),
              const Divider(height: 24, thickness: 0.5),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _isRouteLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF007AFF)),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _routeDuration ?? "Route details...",
                              style: const TextStyle(
                                color: Color(0xFF30D158),
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _routeDistance ?? "",
                              style: TextStyle(
                                color: widget.isDark ? Colors.white60 : Colors.black54,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                  Row(
                    children: [
                      _buildTravelModeButton(
                        mode: 'driving',
                        icon: Icons.directions_car_rounded,
                        tooltip: 'Driving',
                      ),
                      const SizedBox(width: 8),
                      _buildTravelModeButton(
                        mode: 'foot',
                        icon: Icons.directions_walk_rounded,
                        tooltip: 'Walking',
                      ),
                      const SizedBox(width: 8),
                      _buildTravelModeButton(
                        mode: 'bicycle',
                        icon: Icons.directions_bike_rounded,
                        tooltip: 'Cycling',
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _openDirections(h['lat'], h['lon']),
                      icon: const Icon(Icons.navigation_rounded, color: Colors.white),
                      label: const Text(
                        "Start Navigation",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniTab() {
    if (_selectedHospital != null) {
      return _buildDirectionsCard();
    }
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 600),
      curve: Curves.fastLinearToSlowEaseIn,
      bottom: 24,
      left: 16,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _isPanelOpen = !_isPanelOpen),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: widget.isDark ? const Color(0xFF1A1A2E).withOpacity(0.85) : Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: widget.isDark ? Colors.white10 : Colors.black12),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, -5)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.local_hospital_rounded, color: Color(0xFF007AFF), size: 20),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        "Nearby Centers",
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: widget.isDark ? Colors.white : Colors.black87),
                      ),
                      const Spacer(),
                      if (!_isPanelOpen)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF007AFF).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            "${_hospitals.length}",
                            style: const TextStyle(color: Color(0xFF007AFF), fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      const SizedBox(width: 10),
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
          
          if (_isPanelOpen) ...[
            const SizedBox(height: 12),
            Container(
              height: 320,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    decoration: BoxDecoration(
                      color: widget.isDark ? const Color(0xFF1A1A2E).withOpacity(0.75) : Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: widget.isDark ? Colors.white10 : Colors.black12),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Found ${_hospitals.length} locations",
                                style: TextStyle(color: widget.isDark ? Colors.white54 : Colors.black54, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              TextButton.icon(
                                onPressed: () {
                                  if (_currentPosition != null) {
                                    _fetchNearbyHospitals(_currentPosition!.latitude, _currentPosition!.longitude);
                                  }
                                },
                                icon: const Icon(Icons.refresh_rounded, size: 16),
                                label: const Text("Refresh", style: TextStyle(fontSize: 13)),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF007AFF),
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 16, thickness: 0.5),
                        Expanded(
                          child: _hospitals.isEmpty 
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_off_rounded, size: 48, color: widget.isDark ? Colors.white24 : Colors.black26),
                                  const SizedBox(height: 12),
                                  Text("No centers found nearby", style: TextStyle(color: widget.isDark ? Colors.white38 : Colors.black38, fontSize: 15)),
                                  const SizedBox(height: 4),
                                  Text("Try a different search or area", style: TextStyle(color: widget.isDark ? Colors.white24 : Colors.black26, fontSize: 13)),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.only(top: 8),
                                itemCount: _hospitals.length,
                                itemBuilder: (context, index) {
                                  final h = _hospitals[index];
                                  return _hospitalTile(h);
                                },
                              ),
                        ),
                      ],
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
      onTap: () {
        _selectHospital(h);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: widget.isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.02),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: widget.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                h['type'] == 'hospital' ? Icons.local_hospital_rounded : Icons.medical_services_rounded,
                color: const Color(0xFF007AFF),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    h['name'],
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: widget.isDark ? Colors.white : Colors.black87),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on_rounded, size: 12, color: widget.isDark ? Colors.white38 : Colors.black38),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          "${h['distance'].toStringAsFixed(1)} km · ${h['address']}",
                          style: TextStyle(color: widget.isDark ? Colors.white38 : Colors.black38, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF30D158).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.directions_rounded, color: Color(0xFF30D158), size: 22),
                onPressed: () => _selectHospital(h),
              ),
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: widget.isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF007AFF))),
              const SizedBox(width: 12),
              Text("Updating results...", style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600)),
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
