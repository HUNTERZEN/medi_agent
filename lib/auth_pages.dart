import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';

const String _baseUrl = 'https://medi-agent-ser.onrender.com';

class AuthPages extends StatefulWidget {
  const AuthPages({super.key});

  @override
  State<AuthPages> createState() => _AuthPagesState();
}

class _AuthPagesState extends State<AuthPages>
    with SingleTickerProviderStateMixin {
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;

  // Controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Entry animation
  late final AnimationController _entryController;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;
  late final Animation<double> _entryScale;

  // Google Sign-In
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: '872946087974-v4l8g3e7lt2s8sjvd885oj0n4ptom2vh.apps.googleusercontent.com',
  );

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    final curved = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutQuart,
    );

    _entryFade = Tween<double>(begin: 0, end: 1).animate(curved);
    _entrySlide = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(curved);
    _entryScale = Tween<double>(begin: 0.95, end: 1.0).animate(curved);

    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isLogin = !_isLogin;
      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();
    });
  }

  // ── Snackbar Helper ────────────────────────────────────────
  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: isError ? const Color(0xFFFF3B30) : const Color(0xFF34C759),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(20),
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  // ── Validate Inputs ────────────────────────────────────────
  bool _validate() {
    if (!_isLogin && _nameController.text.trim().isEmpty) {
      _showSnackBar("Please enter your name", isError: true);
      return false;
    }
    if (_emailController.text.trim().isEmpty) {
      _showSnackBar("Please enter your email", isError: true);
      return false;
    }
    if (!_emailController.text.contains('@') || !_emailController.text.contains('.')) {
      _showSnackBar("Please enter a valid email", isError: true);
      return false;
    }
    if (_passwordController.text.isEmpty) {
      _showSnackBar("Please enter your password", isError: true);
      return false;
    }
    if (_passwordController.text.length < 6) {
      _showSnackBar("Password must be at least 6 characters", isError: true);
      return false;
    }
    return true;
  }

  // ── Save Auth & Return ─────────────────────────────────────
  Future<void> _saveAuthAndReturn(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', data['token']);
    await prefs.setString('user_name', data['user']['name']);
    await prefs.setString('user_email', data['user']['email']);
    await prefs.setString('auth_provider', data['user']['auth_provider'] ?? 'email');

    if (!mounted) return;
    _showSnackBar("Welcome, ${data['user']['name']}! 🎉");
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) Navigator.of(context).pop(true);
  }

  // ── Email Sign Up ──────────────────────────────────────────
  Future<void> _handleSignUp() async {
    if (!_validate()) return;
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/register'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "name": _nameController.text.trim(),
          "email": _emailController.text.trim().toLowerCase(),
          "password": _passwordController.text,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _saveAuthAndReturn(data);
      } else if (response.statusCode == 409) {
        _showSnackBar("An account with this email already exists", isError: true);
      } else {
        final body = json.decode(response.body);
        _showSnackBar(body['detail'] ?? "Registration failed", isError: true);
      }
    } on TimeoutException {
      _showSnackBar("Server is waking up. Please wait and try again.", isError: true);
    } catch (e) {
      _showSnackBar("Error: ${e.toString()}", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Email Sign In ──────────────────────────────────────────
  Future<void> _handleSignIn() async {
    if (!_validate()) return;
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/login'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "email": _emailController.text.trim().toLowerCase(),
          "password": _passwordController.text,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _saveAuthAndReturn(data);
      } else {
        final body = json.decode(response.body);
        _showSnackBar(body['detail'] ?? "Sign in failed", isError: true);
      }
    } catch (e) {
      _showSnackBar("Could not connect to server. Please try again.", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Google Sign-In ─────────────────────────────────────────
  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        _showSnackBar("Could not get Google credentials", isError: true);
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/google-auth'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({"id_token": idToken}),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _saveAuthAndReturn(data);
      } else {
        final body = json.decode(response.body);
        _showSnackBar(body['detail'] ?? "Google sign-in failed", isError: true);
      }
    } catch (e) {
      _showSnackBar("Google sign-in error. Please try again.", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── UI Builders ────────────────────────────────────────────

  Widget _frostedGlassCard({Key? key, required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        Colors.white.withOpacity(0.12),
                        Colors.white.withOpacity(0.04),
                      ]
                    : [
                        Colors.white.withOpacity(0.8),
                        Colors.white.withOpacity(0.4),
                      ],
              ),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.12)
                    : Colors.white.withOpacity(0.7),
                width: 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop('guest');
        return false;
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: Stack(
          children: [
            // Background Gradient
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    stops: const [0.0, 0.4, 0.6, 1.0],
                    colors: isDark
                        ? const [
                            Color(0xFF080812),
                            Color(0xFF0D1B2A),
                            Color(0xFF1B2838),
                            Color(0xFF080812),
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

            // Ambient Orbs
            Positioned(
              top: -size.width * 0.2,
              right: -size.width * 0.1,
              child: _buildOrb(300, const Color(0xFF007AFF).withOpacity(isDark ? 0.25 : 0.12)),
            ),
            Positioned(
              bottom: size.height * 0.1,
              left: -size.width * 0.2,
              child: _buildOrb(400, const Color(0xFF5856D6).withOpacity(isDark ? 0.2 : 0.08)),
            ),
            Positioned(
              top: size.height * 0.4,
              right: -size.width * 0.2,
              child: _buildOrb(250, const Color(0xFF30D158).withOpacity(isDark ? 0.15 : 0.06)),
            ),

            // Content
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: FadeTransition(
                    opacity: _entryFade,
                    child: SlideTransition(
                      position: _entrySlide,
                      child: ScaleTransition(
                        scale: _entryScale,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 10),
                            // Logo
                            Hero(
                              tag: 'app_logo',
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF007AFF).withOpacity(0.4),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.medical_services_rounded,
                                    color: Colors.white, size: 36),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // App Title
                            Text(
                              "MediAgent",
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.0,
                                color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _isLogin ? "Welcome back" : "Get Started",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white60 : Colors.black45,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Auth Card
                            SizedBox(
                              width: size.width,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 600),
                                switchInCurve: Curves.easeOutQuart,
                                switchOutCurve: Curves.easeInQuart,
                                transitionBuilder: (Widget child, Animation<double> animation) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0.0, 0.05),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  );
                                },
                                child: _isLogin
                                    ? _buildLoginCard(isDark)
                                    : _buildSignUpCard(isDark),
                              ),
                            ),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Custom App Bar Back Button
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 20,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop('guest'),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: isDark ? Colors.white : Colors.black87,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrb(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    );
  }

  Widget _buildLoginCard(bool isDark) {
    return _frostedGlassCard(
      key: const ValueKey('login'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildGoogleButton(isDark),
          const SizedBox(height: 14),
          _buildOrDivider(isDark),
          const SizedBox(height: 14),
          _buildTextField(isDark, "Email", Icons.alternate_email_rounded, _emailController),
          const SizedBox(height: 10),
          _buildTextField(isDark, "Password", Icons.lock_outline_rounded, _passwordController, isPassword: true),
          const SizedBox(height: 20),
          _buildButton("Sign In", _isLoading ? null : _handleSignIn),
          const SizedBox(height: 10),
          _buildGuestButton(isDark),
          const SizedBox(height: 20),
          _buildSwitchText("New here?", "Create Account", _toggleMode, isDark),
        ],
      ),
    );
  }

  Widget _buildSignUpCard(bool isDark) {
    return _frostedGlassCard(
      key: const ValueKey('signup'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildGoogleButton(isDark),
          const SizedBox(height: 14),
          _buildOrDivider(isDark),
          const SizedBox(height: 14),
          _buildTextField(isDark, "Full Name", Icons.person_outline_rounded, _nameController),
          const SizedBox(height: 10),
          _buildTextField(isDark, "Email", Icons.alternate_email_rounded, _emailController),
          const SizedBox(height: 10),
          _buildTextField(isDark, "Password", Icons.lock_outline_rounded, _passwordController, isPassword: true),
          const SizedBox(height: 20),
          _buildButton("Join MediAgent", _isLoading ? null : _handleSignUp),
          const SizedBox(height: 10),
          _buildGuestButton(isDark),
          const SizedBox(height: 20),
          _buildSwitchText("Have an account?", "Sign In Instead", _toggleMode, isDark),
        ],
      ),
    );
  }

  Widget _buildGoogleButton(bool isDark) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.6),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isLoading ? null : _handleGoogleSignIn,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Google G with Custom Colors
              Text(
                "G",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  foreground: Paint()
                    ..shader = const LinearGradient(
                      colors: [Color(0xFF4285F4), Color(0xFF34A853), Color(0xFFFBBC05), Color(0xFFEA4335)],
                    ).createShader(const Rect.fromLTWH(0, 0, 24, 24)),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                "Continue with Google",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white.withOpacity(0.9) : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrDivider(bool isDark) {
    return Row(
      children: [
        Expanded(child: Divider(color: isDark ? Colors.white10 : Colors.black12, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "or with email",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white30 : Colors.black38,
            ),
          ),
        ),
        Expanded(child: Divider(color: isDark ? Colors.white10 : Colors.black12, thickness: 1)),
      ],
    );
  }

  Widget _buildTextField(bool isDark, String hint, IconData icon,
      TextEditingController controller, {bool isPassword = false}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.2) : Colors.white.withOpacity(0.4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
        ),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword && _obscurePassword,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16),
        cursorColor: const Color(0xFF007AFF),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 16),
          prefixIcon: Icon(icon, color: isDark ? Colors.white38 : Colors.black38, size: 22),
          suffixIcon: isPassword
              ? IconButton(
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: isDark ? Colors.white30 : Colors.black38,
                    size: 20,
                  ),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
      ),
    );
  }

  Widget _buildButton(String text, VoidCallback? onPressed) {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF007AFF).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onPressed,
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildGuestButton(bool isDark) {
    return GestureDetector(
      onTap: _isLoading ? null : () => Navigator.of(context).pop('guest'),
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.transparent,
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline_rounded, size: 20, color: isDark ? Colors.white60 : Colors.black54),
            const SizedBox(width: 10),
            Text(
              "Continue as Guest",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchText(String text1, String text2, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: _isLoading ? null : onTap,
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 15),
          children: [
            TextSpan(text: "$text1 "),
            TextSpan(
              text: text2,
              style: const TextStyle(
                color: Color(0xFF007AFF),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
