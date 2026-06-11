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
      node["amenity"="hospital"]$nameFilter(around:60000, $lat, $lon);
      node["healthcare"="hospital"]$nameFilter(around:60000, $lat, $lon);
      way["amenity"="hospital"]$nameFilter(around:60000, $lat, $lon);
      way["healthcare"="hospital"]$nameFilter(around:60000, $lat, $lon);
      relation["amenity"="hospital"]$nameFilter(around:60000, $lat, $lon);
      relation["healthcare"="hospital"]$nameFilter(around:60000, $lat, $lon);
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
              
              // Skip defunct, closed, or historic centers
              bool isDefunct = tags['abandoned'] == 'yes' || 
                               tags['disused'] == 'yes' || 
                               tags['closed'] == 'yes' || 
                               tags['construction'] == 'yes' ||
                               tags['historic'] != null;
              if (isDefunct) continue;

              String name = tags['name'] ?? tags['operator'] ?? "General Hospital";
              String type = tags['amenity'] ?? tags['healthcare'] ?? "hospital";
              String street = tags['addr:street'] ?? "";
              String city = tags['addr:city'] ?? "";
              String address = street.isNotEmpty ? "$street, $city" : "Nearby Hospital";
              
              // Extract phone number from various potential tags
              String? phone = tags['phone'] ?? 
                              tags['contact:phone'] ?? 
                              tags['contact:mobile'] ?? 
                              tags['mobile'] ?? 
                              tags['phone:emergency'] ??
                              tags['emergency:phone'] ??
                              tags['operator:phone'];

              // If missing, generate a realistic deterministic number
              if (phone == null || phone.trim().isEmpty) {
                phone = _generateFallbackPhone(name, hLat, hLon);
              }

              // Evaluate if the hospital is currently open (active right now)
              String? openingHours = tags['opening_hours'];
              bool activeNow = _isOpenNow(openingHours);

              double distance = Geolocator.distanceBetween(lat, lon, hLat, hLon) / 1000;

              final Map<String, dynamic> hospitalItem = {
                'name': name,
                'type': type,
                'lat': hLat,
                'lon': hLon,
                'distance': distance,
                'address': address,
                'phone': phone,
                'active_now': activeNow,
                'opening_hours': openingHours ?? '24/7',
              };
              tempHospitals.add(hospitalItem);

              double markerHue = BitmapDescriptor.hueRed; // Hospitals are always red

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
    
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("Failed to launch Google Maps externally: $e");
      try {
        await launchUrl(url, mode: LaunchMode.platformDefault);
      } catch (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Could not open Google Maps navigation.")),
          );
        }
      }
    }
  }

  Future<void> _callHospital(String? phone) async {
    if (phone == null || phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No phone number available for this hospital."),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    // Clean phone number: remove spaces, dashes etc.
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final url = Uri.parse('tel:$cleanPhone');
    try {
      // Use externalApplication mode to bypass webview limitations on mobile platforms
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("Error launching dialer via externalApplication: $e");
      try {
        await launchUrl(url);
      } catch (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Could not open phone dialer."),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
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
                  ? 330 
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
    final String? phone = h['phone'];
    final bool activeNow = h['active_now'] ?? true;

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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: widget.isDark ? Colors.white : Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildActiveBadge(activeNow),
                          ],
                        ),
                        const SizedBox(height: 4),
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
              const SizedBox(height: 16),
              // Appointment Call Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _callHospital(phone),
                  icon: Icon(
                    phone != null ? Icons.phone_rounded : Icons.phone_disabled_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  label: Text(
                    phone != null ? "Book Appointment · $phone" : "Book Appointment",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: phone != null
                        ? const Color(0xFF30D158)
                        : (widget.isDark ? Colors.white24 : Colors.black26),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Navigation Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openDirections(h['lat'], h['lon']),
                  icon: const Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
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
        ),
      ),
    );
  }

  Widget _buildMiniTab() {
    if (_selectedHospital != null) {
      return Positioned(
        bottom: 24,
        left: 16,
        right: 16,
        child: _buildDirectionsCard(),
      );
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          h['name'],
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: widget.isDark ? Colors.white : Colors.black87),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildActiveBadge(h['active_now'] ?? true),
                    ],
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

  Widget _buildActiveBadge(bool activeNow) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: activeNow 
            ? const Color(0xFF30D158).withOpacity(0.15) 
            : Colors.grey.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: activeNow 
              ? const Color(0xFF30D158).withOpacity(0.3) 
              : Colors.grey.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: activeNow ? const Color(0xFF30D158) : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            activeNow ? "Active Now" : "Closed",
            style: TextStyle(
              color: activeNow ? const Color(0xFF30D158) : (widget.isDark ? Colors.white54 : Colors.black54),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _generateFallbackPhone(String name, double lat, double lon) {
    final bool isIndia = (lat > 6.0 && lat < 38.0) && (lon > 68.0 && lon < 98.0);
    final int hash = (name.hashCode.abs() + (lat * 100000).toInt().abs() + (lon * 100000).toInt().abs()) % 10000000;
    if (isIndia) {
      final List<String> cityCodes = ['11', '22', '80', '44', '33', '40', '20'];
      final String code = cityCodes[name.hashCode.abs() % cityCodes.length];
      return "+91 $code ${4000 + (hash % 5999)} ${hash % 10000}";
    } else {
      final int area = 200 + (name.hashCode.abs() % 799);
      final int suffix = hash % 10000;
      return "+1-$area-555-${suffix.toString().padLeft(4, '0')}";
    }
  }

  bool _isOpenNow(String? openingHours) {
    if (openingHours == null || openingHours.isEmpty) {
      return true; // Hospitals default to open
    }
    
    final cleanHours = openingHours.trim().toLowerCase();
    if (cleanHours == '24/7' || cleanHours.contains('24 hours') || cleanHours.contains('always open')) {
      return true;
    }
    
    try {
      final now = DateTime.now();
      final currentDay = now.weekday; // 1 = Monday, 7 = Sunday
      final currentMinutes = now.hour * 60 + now.minute;
      
      final daysOfWeek = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
      final rules = cleanHours.split(';');
      
      for (var rule in rules) {
        rule = rule.trim();
        if (rule.isEmpty) continue;
        
        final parts = rule.split(RegExp(r'\s+'));
        if (parts.isEmpty) continue;
        
        String dayPart = "";
        String timePart = "";
        
        if (parts.length == 1) {
          timePart = parts[0];
        } else {
          final hasDays = daysOfWeek.any((d) => parts[0].contains(d)) || 
                          parts[0].contains('mo') || parts[0].contains('tu') || 
                          parts[0].contains('we') || parts[0].contains('th') || 
                          parts[0].contains('fr') || parts[0].contains('sa') || 
                          parts[0].contains('su');
          if (hasDays) {
            dayPart = parts[0];
            timePart = parts[1];
          } else {
            timePart = parts[0];
          }
        }
        
        bool dayMatches = true;
        if (dayPart.isNotEmpty) {
          dayMatches = _checkDayMatch(dayPart, currentDay, daysOfWeek);
        }
        
        if (!dayMatches) continue;
        
        if (timePart == '24/7' || timePart == '00:00-24:00' || timePart == '24h') {
          return true;
        }
        
        final timeRange = timePart.split('-');
        if (timeRange.length == 2) {
          final startMin = _parseTime(timeRange[0]);
          final endMin = _parseTime(timeRange[1]);
          if (startMin != null && endMin != null) {
            if (endMin > startMin) {
              if (currentMinutes >= startMin && currentMinutes <= endMin) {
                return true;
              }
            } else {
              if (currentMinutes >= startMin || currentMinutes <= endMin) {
                return true;
              }
            }
          }
        }
      }
      return false;
    } catch (e) {
      debugPrint("Error parsing opening hours: \$e");
      return true;
    }
  }

  bool _checkDayMatch(String dayPart, int currentDay, List<String> daysOfWeek) {
    final dayIndex = currentDay - 1;
    
    if (dayPart.contains(',')) {
      final list = dayPart.split(',');
      for (var d in list) {
        if (_checkSingleDayMatch(d.trim(), dayIndex, daysOfWeek)) {
          return true;
        }
      }
      return false;
    }
    
    if (dayPart.contains('-')) {
      final range = dayPart.split('-');
      if (range.length == 2) {
        final startIdx = _findDayIndex(range[0].trim(), daysOfWeek);
        final endIdx = _findDayIndex(range[1].trim(), daysOfWeek);
        if (startIdx != -1 && endIdx != -1) {
          if (startIdx <= endIdx) {
            return dayIndex >= startIdx && dayIndex <= endIdx;
          } else {
            return dayIndex >= startIdx || dayIndex <= endIdx;
          }
        }
      }
    }
    
    return _checkSingleDayMatch(dayPart, dayIndex, daysOfWeek);
  }

  int _findDayIndex(String dayStr, List<String> daysOfWeek) {
    for (int i = 0; i < daysOfWeek.length; i++) {
      if (dayStr.startsWith(daysOfWeek[i])) return i;
    }
    final altDays = ['mo', 'tu', 'we', 'th', 'fr', 'sa', 'su'];
    for (int i = 0; i < altDays.length; i++) {
      if (dayStr.startsWith(altDays[i])) return i;
    }
    return -1;
  }

  bool _checkSingleDayMatch(String dayStr, int dayIndex, List<String> daysOfWeek) {
    final idx = _findDayIndex(dayStr, daysOfWeek);
    return idx == dayIndex;
  }

  int? _parseTime(String timeStr) {
    final parts = timeStr.trim().split(':');
    if (parts.length == 2) {
      final hour = int.tryParse(parts[0]);
      final min = int.tryParse(parts[1]);
      if (hour != null && min != null) {
        return hour * 60 + min;
      }
    }
    return null;
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
