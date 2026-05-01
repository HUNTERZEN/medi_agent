import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ProfileDashboard extends StatefulWidget {
  final bool isDark;
  final String userName;
  final String userEmail;
  final String authToken;
  final VoidCallback onSignOut;

  const ProfileDashboard({
    super.key,
    required this.isDark,
    required this.userName,
    required this.userEmail,
    required this.authToken,
    required this.onSignOut,
  });

  @override
  State<ProfileDashboard> createState() => _ProfileDashboardState();
}

class _ProfileDashboardState extends State<ProfileDashboard> {
  File? _avatarFile;
  bool _isLoading = true;
  
  // Profile Data
  String _displayName = "";
  String _age = "--";
  String _weight = "--";
  String _height = "--";
  String _heartRate = "--";
  String _sleep = "--";
  String _steps = "0";

  // Notifications
  bool _emailNotifications = true;
  bool _pushNotifications = true;

  // Privacy
  bool _publicProfile = false;
  bool _twoFactorAuth = false;

  final String _baseUrl = 'https://medi-agent-ser.onrender.com';

  @override
  void initState() {
    super.initState();
    _displayName = widget.userName;
    _loadLocalAvatar();
    _fetchProfile();
  }

  Future<void> _loadLocalAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('user_avatar_path');
    if (path != null && File(path).existsSync()) {
      setState(() => _avatarFile = File(path));
    }
  }

  Future<void> _fetchProfile() async {
    if (widget.authToken.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/profile'),
        headers: {
          "Authorization": "Bearer ${widget.authToken}",
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _displayName = data['name'] ?? widget.userName;
          _age = data['age'].toString().isNotEmpty ? data['age'] : "--";
          _weight = data['weight'].toString().isNotEmpty ? data['weight'] : "--";
          _height = data['height'].toString().isNotEmpty ? data['height'] : "--";
          _heartRate = data['heart_rate'].toString().isNotEmpty ? data['heart_rate'] : "--";
          _sleep = data['sleep'].toString().isNotEmpty ? data['sleep'] : "--";
          _steps = data['steps'].toString().isNotEmpty ? data['steps'] : "0";
          _emailNotifications = data['email_notifications'] ?? true;
          _pushNotifications = data['push_notifications'] ?? true;
          _publicProfile = data['public_profile'] ?? false;
          _twoFactorAuth = data['two_factor_auth'] ?? false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching profile: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateProfile(Map<String, dynamic> updates) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/profile/update'),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${widget.authToken}",
        },
        body: json.encode(updates),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        await _fetchProfile();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Settings updated successfully!")),
          );
        }
      }
    } catch (e) {
      debugPrint("Error updating profile: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (image != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_avatar_path', image.path);
      setState(() => _avatarFile = File(image.path));
    }
  }

  void _showEditDialog() {
    final nameController = TextEditingController(text: _displayName);
    final ageController = TextEditingController(text: _age == "--" ? "" : _age);
    final weightController = TextEditingController(text: _weight == "--" ? "" : _weight);
    final heightController = TextEditingController(text: _height == "--" ? "" : _height);
    final hrController = TextEditingController(text: _heartRate == "--" ? "" : _heartRate);
    final sleepController = TextEditingController(text: _sleep == "--" ? "" : _sleep);
    final stepsController = TextEditingController(text: _steps == "0" ? "" : _steps);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Edit Profile"),
        backgroundColor: widget.isDark ? const Color(0xFF1C1C2E) : Colors.white,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildEditField("Name", nameController),
              _buildEditField("Age", ageController),
              _buildEditField("Weight (kg)", weightController),
              _buildEditField("Height (cm)", heightController),
              _buildEditField("Heart Rate (bpm)", hrController),
              _buildEditField("Sleep (h/m)", sleepController),
              _buildEditField("Daily Steps", stepsController),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _updateProfile({
                "name": nameController.text,
                "age": ageController.text,
                "weight": weightController.text,
                "height": heightController.text,
                "heart_rate": hrController.text,
                "sleep": sleepController.text,
                "steps": stepsController.text,
              });
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _showNotificationsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Notifications"),
          backgroundColor: widget.isDark ? const Color(0xFF1C1C2E) : Colors.white,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: Text("Email Notifications", style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87)),
                value: _emailNotifications,
                onChanged: (val) => setDialogState(() => _emailNotifications = val),
              ),
              SwitchListTile(
                title: Text("Push Notifications", style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87)),
                value: _pushNotifications,
                onChanged: (val) => setDialogState(() => _pushNotifications = val),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _updateProfile({
                  "email_notifications": _emailNotifications,
                  "push_notifications": _pushNotifications,
                });
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  void _showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Privacy & Security"),
          backgroundColor: widget.isDark ? const Color(0xFF1C1C2E) : Colors.white,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: Text("Public Profile", style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87)),
                value: _publicProfile,
                onChanged: (val) => setDialogState(() => _publicProfile = val),
              ),
              SwitchListTile(
                title: Text("Two-Factor Auth", style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87)),
                value: _twoFactorAuth,
                onChanged: (val) => setDialogState(() => _twoFactorAuth = val),
              ),
              const Divider(),
              ListTile(
                title: const Text("Change Password", style: TextStyle(color: Color(0xFF007AFF))),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password reset email sent!")));
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _updateProfile({
                  "public_profile": _publicProfile,
                  "two_factor_auth": _twoFactorAuth,
                });
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: widget.isDark ? Colors.white70 : Colors.black54),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: widget.isDark ? Colors.white24 : Colors.black12)),
        ),
        style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87),
      ),
    );
  }

  Widget _frostedContainer({required Widget child, double radius = 24, EdgeInsets? padding}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(widget.isDark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            padding: padding ?? const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.isDark
                    ? [Colors.white.withOpacity(0.12), Colors.white.withOpacity(0.04)]
                    : [Colors.white.withOpacity(0.85), Colors.white.withOpacity(0.6)],
              ),
              border: Border.all(
                color: widget.isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.8),
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
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: widget.isDark ? Colors.white : Colors.black87),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                "Profile Dashboard",
                style: TextStyle(
                  color: widget.isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  letterSpacing: -0.5,
                ),
              ),
              centerTitle: true,
              actions: [
                IconButton(
                  icon: Icon(Icons.edit_note_rounded, color: widget.isDark ? Colors.white : Colors.black87),
                  onPressed: _showEditDialog,
                ),
              ],
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
                  colors: widget.isDark
                      ? const [Color(0xFF0A0A1A), Color(0xFF0D1B2A)]
                      : const [Color(0xFFF0F4FF), Color(0xFFE8ECF4)],
                ),
              ),
            ),
          ),

          SafeArea(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  // Profile Header
                  _frostedContainer(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _pickAvatar,
                          child: Stack(
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF007AFF), Color(0xFF5856D6)],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF007AFF).withOpacity(0.3),
                                      blurRadius: 15,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: _avatarFile != null
                                      ? Image.file(_avatarFile!, fit: BoxFit.cover)
                                      : Center(
                                          child: Text(
                                            _displayName.isNotEmpty ? _displayName[0].toUpperCase() : "?",
                                            style: const TextStyle(
                                                color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(color: Color(0xFF007AFF), shape: BoxShape.circle),
                                  child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _displayName,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: widget.isDark ? Colors.white : Colors.black87,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          widget.userEmail,
                          style: TextStyle(
                            fontSize: 14,
                            color: widget.isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _statItem("Age", _age, Icons.calendar_today_rounded),
                            _statItem("Weight", _weight.contains("kg") ? _weight : "${_weight}kg", Icons.monitor_weight_rounded),
                            _statItem("Height", _height.contains("cm") ? _height : "${_height}cm", Icons.height_rounded),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Health Metrics Section
                  _sectionTitle("Health Summary"),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _metricCard(
                          "Heart Rate",
                          _heartRate.contains("bpm") ? _heartRate : "${_heartRate} bpm",
                          Icons.favorite_rounded,
                          const Color(0xFFFF2D55),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _metricCard(
                          "Sleep",
                          _sleep,
                          Icons.bedtime_rounded,
                          const Color(0xFF5856D6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _metricCard(
                    "Daily Steps",
                    "$_steps / 10,000",
                    Icons.directions_walk_rounded,
                    const Color(0xFF30D158),
                    showProgress: true,
                    progress: (double.tryParse(_steps) ?? 0) / 10000,
                  ),

                  const SizedBox(height: 24),

                  // Quick Actions
                  _sectionTitle("Account Settings"),
                  const SizedBox(height: 12),
                  _frostedContainer(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _settingTile(Icons.person_outline_rounded, "Edit Profile", _showEditDialog),
                        _settingTile(Icons.notifications_none_rounded, "Notifications", _showNotificationsDialog),
                        _settingTile(Icons.security_rounded, "Privacy & Security", _showPrivacyDialog),
                        _settingTile(Icons.help_outline_rounded, "Help & Support", () {}),
                        _settingTile(
                          Icons.logout_rounded,
                          "Sign Out",
                          () {
                            widget.onSignOut();
                            Navigator.pop(context);
                          },
                          isDestructive: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: widget.isDark ? Colors.white : Colors.black87,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF007AFF), size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: widget.isDark ? Colors.white : Colors.black87,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: widget.isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      ],
    );
  }

  Widget _metricCard(String title, String value, IconData icon, Color color,
      {bool showProgress = false, double progress = 0}) {
    return _frostedContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: widget.isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: widget.isDark ? Colors.white : Colors.black87,
              letterSpacing: -0.5,
            ),
          ),
          if (showProgress) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                backgroundColor: color.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 6,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _settingTile(IconData icon, String title, VoidCallback onTap, {bool isDestructive = false}) {
    final color = isDestructive ? const Color(0xFFFF3B30) : (widget.isDark ? Colors.white : Colors.black87);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: color.withOpacity(0.8), size: 22),
              const SizedBox(width: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
              const Spacer(),
              Icon(Icons.chevron_right_rounded,
                  color: widget.isDark ? Colors.white24 : Colors.black26, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
