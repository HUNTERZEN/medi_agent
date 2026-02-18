import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui'; 
import 'dart:io';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart'; // REQUIRED for permanent save

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.dark; 

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black, 
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent),
      ),
      home: MediAgentApp(onThemeToggle: _toggleTheme, currentMode: _themeMode),
    );
  }
}

class MediAgentApp extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final ThemeMode currentMode;
  const MediAgentApp({super.key, required this.onThemeToggle, required this.currentMode});

  @override
  State<MediAgentApp> createState() => _MediAgentAppState();
}

class _MediAgentAppState extends State<MediAgentApp> {
  String _result = "### Welcome to AI Specialist\nUpload multiple reports or ask a question!";
  bool _isLoading = false;
  bool _isMenuOpen = false; 
  File? _wallpaperFile; 
  final List<String> _history = []; 
  final TextEditingController _chatController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSavedWallpaper(); // Load the wallpaper as soon as app opens
  }

  // Load wallpaper path from local storage
  Future<void> _loadSavedWallpaper() async {
    final prefs = await SharedPreferences.getInstance();
    final String? path = prefs.getString('wallpaper_path');
    if (path != null && File(path).existsSync()) {
      setState(() { _wallpaperFile = File(path); });
    }
  }

  // Save wallpaper path permanently
  Future<void> _pickWallpaper() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('wallpaper_path', image.path); 
      setState(() { _wallpaperFile = File(image.path); });
    }
  }

  // NEW: Reset wallpaper to original blue gradient
  Future<void> _resetWallpaper() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('wallpaper_path');
    setState(() { _wallpaperFile = null; });
  }

  Widget _buildGlowGlass({required Widget child, Color glowColor = Colors.blueAccent}) {
    bool isDark = widget.currentMode == ThemeMode.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: isDark ? glowColor.withOpacity(0.15) : glowColor.withOpacity(0.1),
            blurRadius: 25,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25), // Professional liquid blur
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.black.withOpacity(0.4) : Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.2) : Colors.blueAccent.withOpacity(0.2),
                width: 1.5,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  Future<void> _askAiChat() async {
    if (_chatController.text.isEmpty) return;
    setState(() { _isLoading = true; _result = "### 🔍 Searching AI Knowledge..."; });
    try {
      Position? position = await _getCurrentLocation();
      var response = await http.post(
        Uri.parse('http://10.215.207.68:8000/chat'), // UPDATED IP based on your logs
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "prompt": _chatController.text,
          "lat": position?.latitude,
          "lng": position?.longitude,
        }),
      );
      if (response.statusCode == 200) {
        setState(() { _result = json.decode(response.body)['answer']; _chatController.clear(); });
      }
    } catch (e) { setState(() { _result = "## ⚠️ Chat Error: $e"; }); }
    finally { setState(() { _isLoading = false; }); }
  }

  Future<void> _analyzeReport() async {
    final picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage();
    if (images.isEmpty) return;
    setState(() { _isLoading = true; _result = "### ⏳ AI Analyzing & Comparing Reports..."; });
    try {
      Position? position = await _getCurrentLocation();
      var request = http.MultipartRequest('POST', Uri.parse('http://10.215.207.68:8000/analyze'));
      request.fields['lat'] = position?.latitude.toString() ?? "";
      request.fields['lng'] = position?.longitude.toString() ?? "";
      for (var img in images) {
        request.files.add(await http.MultipartFile.fromPath('files', img.path));
      }
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200) {
        String data = json.decode(response.body)['recommendation'];
        setState(() { _result = data; _history.insert(0, data); });
      }
    } catch (e) { setState(() { _result = "## ⚠️ Error: $e"; }); }
    finally { setState(() { _isLoading = false; }); }
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildGlowGlass(
        child: Column(
          children: [
            const Padding(padding: EdgeInsets.all(20), child: Text("Medical History", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
            Expanded(
              child: _history.isEmpty 
                ? const Center(child: Text("No scan history yet."))
                : ListView.builder(
                    itemCount: _history.length,
                    itemBuilder: (context, i) => ListTile(
                      leading: const Icon(Icons.description_outlined, color: Colors.blueAccent),
                      title: Text("Scan Result ${i + 1}", maxLines: 1),
                      onTap: () { setState(() => _result = _history[i]); Navigator.pop(context); },
                    ),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = widget.currentMode == ThemeMode.dark;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("MediAgent: AI Specialist", 
          style: TextStyle(fontWeight: FontWeight.w800, color: isDark ? Colors.white : const Color(0xFF1E293B))),
        elevation: 0,
        actions: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: _isMenuOpen ? 250 : 50, // Wider for the reset icon
            margin: const EdgeInsets.only(right: 10, top: 5, bottom: 5),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_isMenuOpen) ...[
                  IconButton(icon: const Icon(Icons.image_outlined, size: 20), onPressed: _pickWallpaper),
                  IconButton(icon: const Icon(Icons.no_photography_outlined, size: 20), onPressed: _resetWallpaper), // RESET BUTTON
                  IconButton(icon: const Icon(Icons.history, size: 20), onPressed: _showHistory),
                  IconButton(icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, size: 20), onPressed: widget.onThemeToggle),
                ],
                IconButton(icon: Icon(_isMenuOpen ? Icons.close : Icons.menu), onPressed: () => setState(() => _isMenuOpen = !_isMenuOpen)),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Permanent Wallpaper or Gradient
          Positioned.fill(
            child: _wallpaperFile != null
                ? Image.file(_wallpaperFile!, fit: BoxFit.cover)
                : Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark 
                          ? [Colors.black, const Color(0xFF0F172A), const Color(0xFF020617)]
                          : [const Color(0xFFE2E8F0), const Color(0xFFCBD5E1)], 
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                    ),
                  ),
          ),
          Positioned.fill(
            child: Container(
              color: isDark ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.1),
            ),
          ),
          // Content UI Layer
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 110, 18, 20),
            child: Column(
              children: [
                Expanded(
                  child: _buildGlowGlass(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: MarkdownBody(
                              data: _result,
                              selectable: true,
                              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                                h3: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 18),
                                p: TextStyle(fontSize: 15, height: 1.5, color: isDark ? Colors.white.withOpacity(0.9) : Colors.black87),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildGlowGlass(
                  glowColor: Colors.blueAccent.withOpacity(0.4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _chatController,
                            style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1E293B)),
                            decoration: const InputDecoration(hintText: "Ask medical symptoms...", border: InputBorder.none),
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.send_rounded, color: Colors.blueAccent), onPressed: _askAiChat),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_isLoading) const LinearProgressIndicator() else ElevatedButton.icon(
                  onPressed: _analyzeReport,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text("MULTI-REPORT SCAN"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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