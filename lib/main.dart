import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'auth_pages.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui';
import 'dart:io';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'map_page.dart';
import 'profile_dashboard.dart';

// ─────────────────────────────────────────────────────────────
//  Entry
// ─────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Request highest available refresh rate (120Hz / 90Hz) on Android
  try {
    await FlutterDisplayMode.setHighRefreshRate();
  } catch (_) {}
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const MyApp());
}

// ─────────────────────────────────────────────────────────────
//  Root
// ─────────────────────────────────────────────────────────────
class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF2F2F7),
        appBarTheme:
            const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
        splashFactory: InkSparkle.splashFactory,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme:
            const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
        splashFactory: InkSparkle.splashFactory,
      ),
      home: MediAgentApp(
          onThemeToggle: _toggleTheme, currentMode: _themeMode),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Main Screen
// ─────────────────────────────────────────────────────────────
class MediAgentApp extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final ThemeMode currentMode;
  const MediAgentApp(
      {super.key, required this.onThemeToggle, required this.currentMode});

  @override
  State<MediAgentApp> createState() => _MediAgentAppState();
}

class _MediAgentAppState extends State<MediAgentApp>
    with TickerProviderStateMixin {
  String _result =
      "### Hello, I'm Dr. Medi \nYour personal AI medical assistant. Upload your reports for a detailed analysis, or ask me anything about your health — I'm here to help.";
  bool _isLoading = false;
  bool _isMenuOpen = false;
  File? _wallpaperFile;
  final List<String> _history = [];
  final TextEditingController _chatController = TextEditingController();

  // ── Auth state ──
  bool _isLoggedIn = false;
  bool _isGuest = false;
  String _userName = '';
  String _userEmail = '';
  // ignore: unused_field
  String _authProvider = ''; // Reserved for future use (shows auth method in profile)

  // ── Guest usage limits (per day) ──
  static const int _guestChatLimit = 3;
  static const int _guestScanLimit = 3;
  int _guestChatCount = 0;
  int _guestScanCount = 0;

  // ── Animation controllers ──
  late final AnimationController _menuController;
  late final AnimationController _overlayController;
  late final Animation<double> _overlayAnimation;

  bool get _isDark => widget.currentMode == ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadSavedWallpaper();
    _loadSavedHistory();
    _loadSavedAuth();
    _loadGuestUsage();

    _menuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _overlayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _overlayAnimation = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // Show auth page on first launch if not logged in
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFirstLaunchAuth());
  }

  @override
  void dispose() {
    _chatController.dispose();
    _menuController.dispose();
    _overlayController.dispose();
    super.dispose();
  }

  // ── History Persistence ────────────────────────────────────
  Future<void> _loadSavedHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? saved = prefs.getStringList('scan_history');
    if (saved != null && saved.isNotEmpty) {
      setState(() => _history.addAll(saved));
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('scan_history', _history);
  }

  // ── Wallpaper ──────────────────────────────────────────────
  Future<void> _loadSavedWallpaper() async {
    final prefs = await SharedPreferences.getInstance();
    final String? path = prefs.getString('wallpaper_path');
    if (path != null && File(path).existsSync()) {
      setState(() => _wallpaperFile = File(path));
    }
  }

  Future<void> _pickWallpaper() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('wallpaper_path', image.path);
      setState(() => _wallpaperFile = File(image.path));
    }
  }

  // ── Auth Persistence ───────────────────────────────────────
  Future<void> _loadSavedAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final guest = prefs.getBool('is_guest') ?? false;
    if (token != null && token.isNotEmpty) {
      setState(() {
        _isLoggedIn = true;
        _isGuest = false;
        _userName = prefs.getString('user_name') ?? '';
        _userEmail = prefs.getString('user_email') ?? '';
        _authProvider = prefs.getString('auth_provider') ?? 'email';
      });
    } else if (guest) {
      setState(() {
        _isGuest = true;
        _isLoggedIn = false;
      });
    }
  }

  // ── First-launch auth check ────────────────────────────────
  Future<void> _checkFirstLaunchAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final isGuest = prefs.getBool('is_guest') ?? false;
    // If not logged in and not continuing as guest → show auth
    if ((token == null || token.isEmpty) && !isGuest) {
      if (!mounted) return;
      final result = await Navigator.of(context)
          .push<dynamic>(_smoothPageRoute(const AuthPages()));
      if (result == true) {
        // Logged in successfully
        await _loadSavedAuth();
        setState(() {
          _result = "### Welcome, $_userName! 🎉\nI'm Dr. Medi, your personal AI medical assistant. I'm glad to see you. How can I help you today?";
        });
      } else if (result == 'guest') {
        // Entered as guest
        await prefs.setBool('is_guest', true);
        setState(() {
          _isGuest = true;
          _isLoggedIn = false;
          _result = "### Hello! 👋\nYou're using MediAgent in Guest Mode. I can help you with up to 3 chats and 3 scans today. Sign in anytime for unlimited access!";
        });
      }
    } else if (_isLoggedIn && _result.startsWith("### Hello, I'm Dr. Medi")) {
      // If already logged in but still showing default greeting
      setState(() {
        _result = "### Welcome back, $_userName! 👋\nHow are you feeling today? I'm ready to help with your medical reports or any health questions.";
      });
    }
  }

  // ── Guest usage tracking ───────────────────────────────────
  Future<void> _loadGuestUsage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString('guest_usage_date') ?? '';
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (savedDate != today) {
      // Reset daily limits
      await prefs.setString('guest_usage_date', today);
      await prefs.setInt('guest_chat_count', 0);
      await prefs.setInt('guest_scan_count', 0);
      _guestChatCount = 0;
      _guestScanCount = 0;
    } else {
      _guestChatCount = prefs.getInt('guest_chat_count') ?? 0;
      _guestScanCount = prefs.getInt('guest_scan_count') ?? 0;
    }
  }

  Future<void> _incrementGuestChat() async {
    _guestChatCount++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('guest_chat_count', _guestChatCount);
  }

  Future<void> _incrementGuestScan() async {
    _guestScanCount++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('guest_scan_count', _guestScanCount);
  }

  bool _checkGuestChatLimit() {
    if (!_isGuest || _isLoggedIn) return true;
    if (_guestChatCount >= _guestChatLimit) {
      _showGuestLimitDialog('chat');
      return false;
    }
    return true;
  }

  bool _checkGuestScanLimit() {
    if (!_isGuest || _isLoggedIn) return true;
    if (_guestScanCount >= _guestScanLimit) {
      _showGuestLimitDialog('scan');
      return false;
    }
    return true;
  }

  void _showGuestLimitDialog(String type) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _isDark ? const Color(0xFF1C1C2E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Daily Limit Reached',
          style: TextStyle(color: _isDark ? Colors.white : Colors.black87),
        ),
        content: Text(
          'You\'ve used all your free $type${type == 'chat' ? 's' : 's'} for today.\n\nSign in to get unlimited access!',
          style: TextStyle(color: _isDark ? Colors.white70 : Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Later', style: TextStyle(color: _isDark ? Colors.white54 : Colors.black45)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await Navigator.of(context)
                  .push<dynamic>(_smoothPageRoute(const AuthPages()));
              if (result == true) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('is_guest');
                _loadSavedAuth();
              }
            },
            child: const Text('Sign In', style: TextStyle(color: Color(0xFF007AFF), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSignOut() async {
    // Sign out from Google if applicable
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_name');
    await prefs.remove('user_email');
    await prefs.remove('auth_provider');
    await prefs.remove('is_guest');
    setState(() {
      _isLoggedIn = false;
      _isGuest = false;
      _userName = '';
      _userEmail = '';
      _authProvider = '';
    });
    // Show auth page again after sign out
    if (mounted) {
      _checkFirstLaunchAuth();
    }
  }

  Future<void> _resetWallpaper() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('wallpaper_path');
    setState(() => _wallpaperFile = null);
  }

  // ── Location ───────────────────────────────────────────────
  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Prompt user to enable location services
      final shouldOpen = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Location Services Disabled"),
          content: const Text(
              "Please enable location services so we can find nearby clinics and hospitals for you."),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Not Now")),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Open Settings")),
          ],
        ),
      );
      if (shouldOpen == true) {
        await Geolocator.openLocationSettings();
      }
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) {
      // Permission permanently denied — guide user to app settings
      final shouldOpen = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Location Permission Required"),
          content: const Text(
              "Location access was permanently denied. Please enable it in your app settings to find nearby doctors."),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Cancel")),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Open Settings")),
          ],
        ),
      );
      if (shouldOpen == true) {
        await Geolocator.openAppSettings();
      }
      return null;
    }

    return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
  }

  // ── AI Chat ────────────────────────────────────────────────
  Future<void> _askAiChat() async {
    if (_chatController.text.isEmpty) return;
    if (!_checkGuestChatLimit()) return;
    setState(() {
      _isLoading = true;
      _result = "### Give me a moment...\nI'm looking into this for you.";
    });
    try {
      Position? position = await _getCurrentLocation();
      var response = await http.post(
        // UPDATED URL HERE:
        Uri.parse('https://medi-agent-ser.onrender.com/chat'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "prompt": _chatController.text,
          "lat": position?.latitude,
          "lng": position?.longitude,
        }),
      ).timeout(const Duration(seconds: 90));

      if (response.statusCode == 200) {
        if (_isGuest && !_isLoggedIn) await _incrementGuestChat();
        setState(() {
          _result = json.decode(response.body)['answer'];
          _chatController.clear();
        });
      } else {
        setState(() => _result = "## ⚠️ Server Error\nI'm having trouble connecting to my medical database (Status: ${response.statusCode}). Please try again in a moment.");
      }
    } on TimeoutException {
      setState(() => _result = "## ⏱️ Connection Timeout\nThe server is taking a bit longer to wake up. Please try again.");
    } catch (e) {
      setState(() => _result = "## Something went wrong\nI couldn't process your question right now. Please check your connection and try again. Error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── Report Scan ────────────────────────────────────────────
  Future<void> _analyzeReport() async {
    if (!_checkGuestScanLimit()) return;
    final picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage();
    if (images.isEmpty) return;
    setState(() {
      _isLoading = true;
      _result = "### Reviewing your reports...\nI'm carefully analyzing the details. This may take a moment.";
    });
    try {
      Position? position = await _getCurrentLocation();
      var request = http.MultipartRequest(
          // UPDATED URL HERE:
          'POST', Uri.parse('https://medi-agent-ser.onrender.com/analyze'));
      request.fields['lat'] = position?.latitude.toString() ?? "";
      request.fields['lng'] = position?.longitude.toString() ?? "";
      for (var img in images) {
        request.files
            .add(await http.MultipartFile.fromPath('files', img.path));
      }
      var streamedResponse = await request.send().timeout(const Duration(seconds: 120));
      var response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode == 200) {
        if (_isGuest && !_isLoggedIn) await _incrementGuestScan();
        String data = json.decode(response.body)['recommendation'];
        setState(() {
          _result = data;
          _history.insert(0, data);
        });
        await _saveHistory();
      } else {
        setState(() => _result = "## ⚠️ Analysis Error\nI couldn't complete the scan (Status: ${response.statusCode}). The server might be busy. Please try again later.");
      }
    } on TimeoutException {
      setState(() => _result = "## ⏱️ Scan Timeout\nAnalyzing reports can take time, but this is taking longer than usual. Please try again.");
    } catch (e) {
      setState(() => _result = "## ⚠️ Scan Error\n$e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── iOS 26 Frosted Glass Container ─────────────────────────
  Widget _frostedGlass({
    required Widget child,
    double blur = 40,
    double radius = 24,
    EdgeInsets padding = EdgeInsets.zero,
    Color? glowColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          if (glowColor != null)
            BoxShadow(
                color: glowColor.withOpacity(0.12),
                blurRadius: 30,
                spreadRadius: -5)
          else
            BoxShadow(
                color: Colors.black.withOpacity(_isDark ? 0.25 : 0.06),
                blurRadius: 20,
                offset: const Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _isDark
                    ? [
                        Colors.white.withOpacity(0.12),
                        Colors.white.withOpacity(0.05),
                      ]
                    : [
                        Colors.white.withOpacity(0.78),
                        Colors.white.withOpacity(0.55),
                      ],
              ),
              border: Border.all(
                color: _isDark
                    ? Colors.white.withOpacity(0.14)
                    : Colors.white.withOpacity(0.9),
                width: 0.5,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  // ── History Sheet ──────────────────────────────────────────
  void _showHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (context, scrollController) => ClipRRect(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
            child: Container(
              decoration: BoxDecoration(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: _isDark
                      ? [
                          Colors.white.withOpacity(0.14),
                          Colors.white.withOpacity(0.07),
                        ]
                      : [
                          Colors.white.withOpacity(0.88),
                          Colors.white.withOpacity(0.75),
                        ],
                ),
                border: Border(
                  top: BorderSide(
                    color: _isDark
                        ? Colors.white.withOpacity(0.2)
                        : Colors.white,
                    width: 0.5,
                  ),
                ),
              ),
              child: Column(
                children: [
                  // Drag handle
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _isDark
                          ? Colors.white.withOpacity(0.3)
                          : Colors.black.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF007AFF).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.history_rounded,
                              color: Color(0xFF007AFF), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          "Scan History",
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            letterSpacing: -0.5,
                            color: _isDark
                                ? Colors.white
                                : const Color(0xFF1C1C1E),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          "${_history.length} results",
                          style: TextStyle(
                            fontSize: 14,
                            color: _isDark
                                ? Colors.white.withOpacity(0.5)
                                : Colors.black.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: _isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.black.withOpacity(0.06),
                  ),
                  Expanded(
                    child: _history.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.document_scanner_outlined,
                                    size: 48,
                                    color: _isDark
                                        ? Colors.white.withOpacity(0.2)
                                        : Colors.black.withOpacity(0.15)),
                                const SizedBox(height: 12),
                                Text(
                                  "No scan history yet",
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: _isDark
                                        ? Colors.white.withOpacity(0.4)
                                        : Colors.black.withOpacity(0.35),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            itemCount: _history.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) => Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  setState(
                                      () => _result = _history[i]);
                                  Navigator.pop(context);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    borderRadius:
                                        BorderRadius.circular(16),
                                    color: _isDark
                                        ? Colors.white.withOpacity(0.06)
                                        : Colors.black.withOpacity(0.03),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          gradient:
                                              const LinearGradient(
                                            colors: [
                                              Color(0xFF007AFF),
                                              Color(0xFF5856D6),
                                            ],
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            "${i + 1}",
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "Scan Result ${i + 1}",
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                                color: _isDark
                                                    ? Colors.white
                                                    : const Color(
                                                        0xFF1C1C1E),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _history[i].length > 60
                                                  ? "${_history[i].substring(0, 60)}..."
                                                  : _history[i],
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: _isDark
                                                    ? Colors.white
                                                        .withOpacity(0.5)
                                                    : Colors.black
                                                        .withOpacity(0.4),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: _isDark
                                            ? Colors.white
                                                .withOpacity(0.3)
                                            : Colors.black
                                                .withOpacity(0.2),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Menu Toggle ────────────────────────────────────────────
  void _toggleMenu() {
    setState(() => _isMenuOpen = !_isMenuOpen);
    if (_isMenuOpen) {
      _menuController.forward(from: 0);
      _overlayController.forward(from: 0);
    } else {
      _menuController.reverse();
      _overlayController.reverse();
    }
  }

  // ── Staggered Menu Item ────────────────────────────────────
  Widget _staggeredMenuItem({
    required int index,
    required int total,
    required Widget child,
  }) {
    // Each item gets a staggered delay within the overall animation
    final double start = (index / total) * 0.4;
    final double end = start + 0.6;
    final curvedAnim = CurvedAnimation(
      parent: _menuController,
      curve: Interval(start.clamp(0.0, 1.0), end.clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: curvedAnim,
      builder: (context, ch) {
        return Transform.translate(
          offset: Offset(0, 12 * (1 - curvedAnim.value)),
          child: Opacity(
            opacity: curvedAnim.value,
            child: Transform.scale(
              scale: 0.92 + 0.08 * curvedAnim.value,
              alignment: Alignment.topRight,
              child: ch,
            ),
          ),
        );
      },
      child: child,
    );
  }

  // ── Dropdown Menu Overlay ──────────────────────────────────
  Widget _buildDropMenu() {
    final items = <Widget>[];
    // Adjust total count for staggered animations
    int totalItems = (_isLoggedIn ? 7 : (_isGuest ? 5 : 4)) + (_wallpaperFile != null ? 1 : 0);
    int idx = 0;

    // ── User profile or Sign In ──
    if (_isLoggedIn) {
      items.add(_staggeredMenuItem(
        index: idx++,
        total: totalItems,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              _toggleMenu();
              final prefs = await SharedPreferences.getInstance();
              final token = prefs.getString('auth_token') ?? '';
              if (!mounted) return;
              Navigator.of(context).push(
                _smoothPageRoute(ProfileDashboard(
                  isDark: _isDark,
                  userName: _userName,
                  userEmail: _userEmail,
                  authToken: token,
                  onSignOut: _handleSignOut,
                )),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _userName.isNotEmpty ? _userName[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _userName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _userEmail,
                          style: TextStyle(
                            fontSize: 11,
                            color: _isDark ? Colors.white38 : Colors.black45,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 16, color: _isDark ? Colors.white24 : Colors.black26),
                ],
              ),
            ),
          ),
        ),
      ));

      items.add(Divider(color: _isDark ? Colors.white24 : Colors.black12, height: 16));

      items.add(_staggeredMenuItem(
        index: idx++,
        total: totalItems,
        child: _menuItem(
          icon: Icons.dashboard_customize_rounded,
          title: "Profile Dashboard",
          onTap: () async {
            _toggleMenu();
            final prefs = await SharedPreferences.getInstance();
            final token = prefs.getString('auth_token') ?? '';
            if (!mounted) return;
            Navigator.of(context).push(
              _smoothPageRoute(ProfileDashboard(
                isDark: _isDark,
                userName: _userName,
                userEmail: _userEmail,
                authToken: token,
                onSignOut: _handleSignOut,
              )),
            );
          },
        ),
      ));
    } else {
      // Guest mode indicator
      if (_isGuest) {
        items.add(_staggeredMenuItem(
          index: idx++,
          total: totalItems,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: _isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
                  ),
                  child: Icon(Icons.person_outline_rounded, color: _isDark ? Colors.white54 : Colors.black45, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Guest Mode', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _isDark ? Colors.white : Colors.black87)),
                      Text(
                        '${_guestChatLimit - _guestChatCount} chats · ${_guestScanLimit - _guestScanCount} scans left today',
                        style: TextStyle(fontSize: 11, color: _isDark ? Colors.white38 : Colors.black45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ));
        items.add(Divider(color: _isDark ? Colors.white24 : Colors.black12, height: 16));
      }

      items.add(_staggeredMenuItem(
        index: idx++,
        total: totalItems,
        child: _menuItem(
          icon: Icons.login_rounded,
          title: "Sign In / Sign Up",
          color: const Color(0xFF007AFF),
          onTap: () async {
            _toggleMenu();
            final result = await Navigator.of(context)
                .push<dynamic>(_smoothPageRoute(const AuthPages()));
            if (result == true) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('is_guest');
              _loadSavedAuth();
            }
          },
        ),
      ));
    }

    items.add(Divider(color: _isDark ? Colors.white24 : Colors.black12, height: 16));

    // History remains restricted to logged-in users
    if (_isLoggedIn) {
      items.add(_staggeredMenuItem(
        index: idx++,
        total: totalItems,
        child: _menuItem(
          icon: Icons.history_rounded,
          title: "Scan History",
          onTap: () {
            _toggleMenu();
            _showHistory();
          },
        ),
      ));
    }

    // Hospitals is now available for everyone
    items.add(_staggeredMenuItem(
      index: idx++,
      total: totalItems,
      child: _menuItem(
        icon: Icons.map_rounded,
        title: "Nearest Hospitals",
        onTap: () {
          _toggleMenu();
          Navigator.of(context).push(
            _smoothPageRoute(HospitalMapPage(isDark: _isDark)),
          );
        },
      ),
    ));

    items.add(_staggeredMenuItem(
      index: idx++,
      total: totalItems,
      child: _menuItem(
        icon: Icons.photo_library_outlined,
        title: "Change Wallpaper",
        onTap: () {
          _toggleMenu();
          _pickWallpaper();
        },
      ),
    ));

    if (_wallpaperFile != null) {
      items.add(_staggeredMenuItem(
        index: idx++,
        total: totalItems,
        child: _menuItem(
          icon: Icons.wallpaper_outlined,
          title: "Reset Wallpaper",
          onTap: () {
            _toggleMenu();
            _resetWallpaper();
          },
        ),
      ));
    }

    items.add(_staggeredMenuItem(
      index: idx++,
      total: totalItems,
      child: _menuItem(
        icon: _isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
        title: _isDark ? "Light Mode" : "Dark Mode",
        onTap: () {
          _toggleMenu();
          widget.onThemeToggle();
        },
      ),
    ));

    return _frostedGlass(
      radius: 20,
      blur: 40,
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 220,
        child: Column(children: items),
      ),
    );
  }

  // ── Smooth Page Route (slide up + fade) ────────────────────
  Route<T> _smoothPageRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 500),
      reverseTransitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curved),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Widget _menuItem({required IconData icon, required String title, required VoidCallback onTap, Color? color}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color ?? (_isDark ? Colors.white70 : Colors.black87)),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: color != null ? FontWeight.w600 : FontWeight.w500,
                  color: color ?? (_isDark ? Colors.white : Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        extendBody: true,
        body: Stack(
          children: [
            // ── Background ──
            Positioned.fill(
              child: _wallpaperFile != null
                  ? Image.file(_wallpaperFile!, fit: BoxFit.cover)
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          stops: const [0.0, 0.3, 0.7, 1.0],
                          colors: _isDark
                              ? const [
                                  Color(0xFF0A0A1A),
                                  Color(0xFF0D1B2A),
                                  Color(0xFF1B2838),
                                  Color(0xFF0A0A1A),
                                ]
                              : const [
                                  Color(0xFFF0F4FF),
                                  Color(0xFFE8ECF4),
                                  Color(0xFFF5F0FF),
                                  Color(0xFFEEF2F7),
                                ],
                        ),
                      ),
                    ),
            ),

            // ── Ambient Orbs (iOS-style depth) ──
            if (_wallpaperFile == null) ...[
              Positioned(
                top: -60,
                right: -40,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      const Color(0xFF007AFF)
                          .withOpacity(_isDark ? 0.25 : 0.12),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
              Positioned(
                bottom: 120,
                left: -80,
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      const Color(0xFF5856D6)
                          .withOpacity(_isDark ? 0.2 : 0.08),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
              Positioned(
                top: 300,
                right: -60,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      const Color(0xFF30D158)
                          .withOpacity(_isDark ? 0.12 : 0.06),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
            ],

            // ── Overlay tint ──
            Positioned.fill(
              child: Container(
                color: _isDark
                    ? Colors.black.withOpacity(0.2)
                    : Colors.white.withOpacity(0.05),
              ),
            ),

            // ── Content ──
            SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    EdgeInsets.fromLTRB(16, 0, 16, bottomPadding + 16),
                child: Column(
                  children: [
                    // ── Glass App Bar ──
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 12),
                      child: _frostedGlass(
                        radius: 20,
                        blur: 40,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF007AFF),
                                    Color(0xFF5856D6),
                                  ],
                                ),
                              ),
                              child: const Icon(
                                  Icons.medical_services_rounded,
                                  color: Colors.white,
                                  size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "MediAgent",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 17,
                                      letterSpacing: -0.3,
                                      color: _isDark
                                          ? Colors.white
                                          : const Color(0xFF1C1C1E),
                                    ),
                                  ),
                                  Text(
                                    "Your Personal Health Assistant",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: _isDark
                                          ? Colors.white.withOpacity(0.5)
                                          : Colors.black.withOpacity(0.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Hamburger Button with animated icon
                            GestureDetector(
                              onTap: _toggleMenu,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: _isDark
                                      ? Colors.white.withOpacity(_isMenuOpen ? 0.2 : 0.08)
                                      : Colors.black.withOpacity(_isMenuOpen ? 0.1 : 0.04),
                                ),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) {
                                    return RotationTransition(
                                      turns: Tween<double>(begin: 0.75, end: 1.0).animate(animation),
                                      child: ScaleTransition(
                                        scale: animation,
                                        child: FadeTransition(
                                          opacity: animation,
                                          child: child,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Icon(
                                    _isMenuOpen ? Icons.close_rounded : Icons.menu_rounded,
                                    key: ValueKey(_isMenuOpen),
                                    size: 22,
                                    color: _isDark
                                        ? Colors.white.withOpacity(0.9)
                                        : Colors.black.withOpacity(0.7),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Result Card ──
                    Expanded(
                      child: _frostedGlass(
                        blur: 50,
                        glowColor: const Color(0xFF007AFF),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.all(18),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: MarkdownBody(
                                  key: ValueKey(_result.hashCode),
                                  data: _result,
                                  selectable: true,
                                styleSheet:
                                    MarkdownStyleSheet.fromTheme(
                                            Theme.of(context))
                                        .copyWith(
                                  h3: const TextStyle(
                                    color: Color(0xFF007AFF),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 19,
                                    letterSpacing: -0.3,
                                  ),
                                  p: TextStyle(
                                    fontSize: 15,
                                    height: 1.6,
                                    letterSpacing: -0.1,
                                    color: _isDark
                                        ? Colors.white
                                            .withOpacity(0.88)
                                        : const Color(0xFF1C1C1E),
                                  ),
                                  listBullet: TextStyle(
                                    color: _isDark
                                        ? Colors.white
                                            .withOpacity(0.6)
                                        : Colors.black
                                            .withOpacity(0.5),
                                  ),
                                  blockquoteDecoration:
                                      BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                        color: const Color(0xFF007AFF)
                                            .withOpacity(0.4),
                                        width: 3,
                                      ),
                                    ),
                                    color: const Color(0xFF007AFF)
                                        .withOpacity(0.06),
                                    borderRadius:
                                        BorderRadius.circular(4),
                                  ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── Chat Input ──
                    _frostedGlass(
                      blur: 50,
                      radius: 20,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _chatController,
                              style: TextStyle(
                                fontSize: 15,
                                letterSpacing: -0.2,
                                color: _isDark
                                    ? Colors.white
                                    : const Color(0xFF1C1C1E),
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    "Describe your symptoms or ask me anything...",
                                hintStyle: TextStyle(
                                  color: _isDark
                                      ? Colors.white.withOpacity(0.35)
                                      : Colors.black.withOpacity(0.3),
                                  fontSize: 15,
                                  letterSpacing: -0.2,
                                ),
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        vertical: 12),
                              ),
                              onSubmitted: (_) => _askAiChat(),
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              borderRadius:
                                  BorderRadius.circular(14),
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF007AFF),
                                  Color(0xFF5856D6),
                                ],
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius:
                                    BorderRadius.circular(14),
                                onTap: _askAiChat,
                                child: const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(
                                      Icons.arrow_upward_rounded,
                                      color: Colors.white,
                                      size: 20),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── Scan Button / Loading ──
                    if (_isLoading)
                      _frostedGlass(
                        radius: 20,
                        blur: 30,
                        padding:
                            const EdgeInsets.symmetric(vertical: 18),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(
                                  const Color(0xFF007AFF)
                                      .withOpacity(0.8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              "Looking into it...",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: _isDark
                                    ? Colors.white
                                        .withOpacity(0.7)
                                    : Colors.black
                                        .withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(20),
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF007AFF),
                              Color(0xFF5856D6),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF007AFF)
                                  .withOpacity(0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius:
                                BorderRadius.circular(20),
                            onTap: _analyzeReport,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                  vertical: 16),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(
                                      Icons
                                          .document_scanner_rounded,
                                      color: Colors.white,
                                      size: 20),
                                  SizedBox(width: 10),
                                  Text(
                                    "Scan Medical Reports",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight:
                                          FontWeight.w600,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            
            // ── Animated Overlay Backdrop ──
            if (_isMenuOpen)
              AnimatedBuilder(
                animation: _overlayAnimation,
                builder: (context, _) {
                  return Positioned.fill(
                    child: GestureDetector(
                      onTap: _toggleMenu,
                      child: Container(
                        color: Colors.black.withOpacity(0.35 * _overlayAnimation.value),
                      ),
                    ),
                  );
                },
              ),

            // ── Animated Menu Dropdown ──
            AnimatedBuilder(
              animation: _menuController,
              builder: (context, child) {
                final curved = CurvedAnimation(
                  parent: _menuController,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                );
                if (curved.value == 0) return const SizedBox.shrink();
                return Positioned(
                  top: MediaQuery.of(context).padding.top + 70,
                  right: 16,
                  child: Transform.scale(
                    scale: 0.85 + 0.15 * curved.value,
                    alignment: Alignment.topRight,
                    child: Opacity(
                      opacity: curved.value,
                      child: _buildDropMenu(),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}