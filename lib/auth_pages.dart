import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:convert';
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
      duration: const Duration(milliseconds: 700),
    );

    final curved = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );

    _entryFade = Tween<double>(begin: 0, end: 1).animate(curved);
    _entrySlide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(curved);
    _entryScale = Tween<double>(begin: 0.92, end: 1.0).animate(curved);

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
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w500)),
        backgroundColor: isError ? const Color(0xFFFF3B30) : const Color(0xFF34C759),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
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
    if (mounted) Navigator.of(context).pop(true); // Return true = success
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
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await _saveAuthAndReturn(data);
      } else if (response.statusCode == 409) {
        _showSnackBar("An account with this email already exists", isError: true);
      } else {
        final body = json.decode(response.body);
        _showSnackBar(body['detail'] ?? "Registration failed", isError: true);
      }
    } catch (e) {
      _showSnackBar("Could not connect to server. Please try again.", isError: true);
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
      );

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
        // User cancelled
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

      // Send ID token to our backend
      final response = await http.post(
        Uri.parse('$_baseUrl/google-auth'),
        headers: {"Content-Type": "application/json"},
        body: json.encode({"id_token": idToken}),
      );

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
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.1),
            blurRadius: 40,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        Colors.white.withOpacity(0.14),
                        Colors.white.withOpacity(0.06),
                      ]
                    : [
                        Colors.white.withOpacity(0.85),
                        Colors.white.withOpacity(0.55),
                      ],
              ),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.18)
                    : Colors.white.withOpacity(0.95),
                width: 0.5,
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

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.black.withOpacity(0.04),
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
      body: Stack(
        children: [
          // Background Gradient
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: const [0.0, 0.3, 0.7, 1.0],
                  colors: isDark
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

          // Ambient Orbs
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFF007AFF).withOpacity(isDark ? 0.3 : 0.15),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            left: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFF5856D6).withOpacity(isDark ? 0.25 : 0.1),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Positioned(
            top: 350,
            right: -50,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFF30D158).withOpacity(isDark ? 0.15 : 0.08),
                  Colors.transparent,
                ]),
              ),
            ),
          ),

          // Content with entry animation
          Center(
            child: SingleChildScrollView(
              child: FadeTransition(
                opacity: _entryFade,
                child: SlideTransition(
                  position: _entrySlide,
                  child: ScaleTransition(
                    scale: _entryScale,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Logo
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF007AFF).withOpacity(0.45),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                              BoxShadow(
                                color: const Color(0xFF5856D6).withOpacity(0.2),
                                blurRadius: 40,
                                offset: const Offset(0, 16),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.medical_services_rounded,
                              color: Colors.white, size: 38),
                        ),
                        const SizedBox(height: 24),

                        // App Title
                        Text(
                          "MediAgent",
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                          ),
                        ),
                        const SizedBox(height: 44),

                        // Auth Card
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 550),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (Widget child, Animation<double> animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.0, 0.06),
                                  end: Offset.zero,
                                ).animate(CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic,
                                )),
                                child: ScaleTransition(
                                  scale: Tween<double>(begin: 0.96, end: 1.0)
                                      .animate(CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  )),
                                  child: child,
                                ),
                              ),
                            );
                          },
                          layoutBuilder: (Widget? current, List<Widget> previous) {
                            return Stack(
                              alignment: Alignment.topCenter,
                              children: [...previous, if (current != null) current],
                            );
                          },
                          child: _isLogin
                              ? _buildLoginCard(isDark)
                              : _buildSignUpCard(isDark),
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
    );
  }

  Widget _buildLoginCard(bool isDark) {
    return _frostedGlassCard(
      key: const ValueKey('login'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("Welcome back",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.3,
                color: isDark ? Colors.white : Colors.black87,
              )),
          const SizedBox(height: 8),
          Text("Sign in to continue",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: isDark ? Colors.white60 : Colors.black54)),
          const SizedBox(height: 28),

          // Google Sign-In Button
          _buildGoogleButton(isDark),
          const SizedBox(height: 20),

          // Divider
          _buildOrDivider(isDark),
          const SizedBox(height: 20),

          _buildTextField(isDark, "Email", Icons.email_outlined, _emailController),
          const SizedBox(height: 14),
          _buildTextField(isDark, "Password", Icons.lock_outline, _passwordController, isPassword: true),
          const SizedBox(height: 28),
          _buildButton("Sign In", _isLoading ? null : _handleSignIn),
          const SizedBox(height: 24),
          _buildSwitchText("Don't have an account?", "Sign Up", _toggleMode, isDark),
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
          Text("Create Account",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.3,
                color: isDark ? Colors.white : Colors.black87,
              )),
          const SizedBox(height: 8),
          Text("Join MediAgent today",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: isDark ? Colors.white60 : Colors.black54)),
          const SizedBox(height: 28),

          // Google Sign-In Button
          _buildGoogleButton(isDark),
          const SizedBox(height: 20),

          // Divider
          _buildOrDivider(isDark),
          const SizedBox(height: 20),

          _buildTextField(isDark, "Full Name", Icons.person_outline, _nameController),
          const SizedBox(height: 14),
          _buildTextField(isDark, "Email", Icons.email_outlined, _emailController),
          const SizedBox(height: 14),
          _buildTextField(isDark, "Password", Icons.lock_outline, _passwordController, isPassword: true),
          const SizedBox(height: 28),
          _buildButton("Create Account", _isLoading ? null : _handleSignUp),
          const SizedBox(height: 24),
          _buildSwitchText("Already have an account?", "Sign In", _toggleMode, isDark),
        ],
      ),
    );
  }

  // ── Google Button ──────────────────────────────────────────
  Widget _buildGoogleButton(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.15 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isLoading ? null : _handleGoogleSignIn,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Google "G" logo using text
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      "G",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        foreground: Paint()
                          ..shader = const LinearGradient(
                            colors: [
                              Color(0xFF4285F4),
                              Color(0xFF34A853),
                              Color(0xFFFBBC05),
                              Color(0xFFEA4335),
                            ],
                          ).createShader(const Rect.fromLTWH(0, 0, 22, 22)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  "Continue with Google",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── "OR" Divider ───────────────────────────────────────────
  Widget _buildOrDivider(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 0.5,
            color: isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.1),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "or",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 0.5,
            color: isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.1),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(bool isDark, String hint, IconData icon,
      TextEditingController controller, {bool isPassword = false}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.25) : Colors.white.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
        ),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword && _obscurePassword,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
        cursorColor: const Color(0xFF007AFF),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 15),
          prefixIcon: Icon(icon, color: isDark ? Colors.white54 : Colors.black54, size: 20),
          suffixIcon: isPassword
              ? GestureDetector(
                  onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                  child: Icon(
                    _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: isDark ? Colors.white38 : Colors.black38,
                    size: 20,
                  ),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildButton(String text, VoidCallback? onPressed) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: _isLoading ? 0.7 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF007AFF).withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            splashColor: Colors.white.withOpacity(0.15),
            highlightColor: Colors.white.withOpacity(0.05),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 17),
              child: _isLoading
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                    )
                  : Text(
                      text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchText(String text1, String text2, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: _isLoading ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 14),
            children: [
              TextSpan(text: "$text1 "),
              TextSpan(
                text: text2,
                style: const TextStyle(
                  color: Color(0xFF007AFF),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
