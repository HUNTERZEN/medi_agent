# 🩺 MediAgent — Project Progress Summary
> **Presentation Document** | AI-Powered Medical Report Analysis & Specialist Finder  
> Version: **2.1.0** | Platform: **Flutter (Android & iOS)**

---

## 📌 What is MediAgent?

MediAgent is an intelligent mobile healthcare assistant that uses Artificial Intelligence to:

- **Simplify complex medical reports** into plain language that any patient can understand
- **Detect health trends** across multiple uploaded reports over time
- **Recommend the right specialist** based on AI analysis results
- **Find nearby hospitals/clinics** using real-time GPS location

The goal is to bridge the gap between confusing clinical data and patient understanding — empowering users to take faster, smarter healthcare decisions.

---

## 🏗️ System Architecture

```
Flutter App  (Mobile Frontend)
      ↓
Python FastAPI Backend  (main.py)
      ↓
Google Gemini 2.5 Flash  (AI Model)
      ↓
Firebase  (Cloud Storage & Auth)
      ↓
Google Maps API + GPS  (Hospital Finder)
```

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| 📱 Mobile App | Flutter (Dart) — Android & iOS |
| 🤖 AI Engine | Google Gemini 2.5 Flash |
| 🔧 Backend Server | Python (FastAPI) |
| ☁️ Cloud & Auth | Firebase |
| 🗺️ Maps & Location | Google Maps API + Geolocator (GPS) |
| 🔐 Authentication | Firebase Auth (Email/Password + Google Sign-In) |

---

## ✅ Progress Made — What Has Been Built

### 1. 🔐 Authentication System
- Full **Login / Sign-Up** screen with animated UI
- **Email & Password** authentication via backend API
- **Google Sign-In** (one-tap sign-in support)
- Persistent login sessions using **SharedPreferences**
- Graceful error handling with user-friendly Snackbar messages
- Timeout handling for slow network/cold-start server responses

### 2. 🧠 AI Medical Report Analysis (Core Feature)
- Users can **upload one or multiple medical report images**
- Reports are sent to the **Python FastAPI backend**
- Backend forwards to **Google Gemini 2.5 Flash** for analysis
- AI returns:
  - Plain-language summary of findings
  - Detected health trends (improving / worsening / stable)
  - Recommended medical specialist type
- Results rendered with **Flutter Markdown** for clean, readable formatting

### 3. 💬 AI Chat Interface ("Dr. Medi")
- Full **chat-style interface** with the AI assistant
- Conversation history maintained within the session
- Greeting adapts based on whether user is logged in or not
- Supports freeform health questions beyond just report uploads

### 4. 🗺️ Hospital Finder Map (Real-Time GPS)
- Dedicated **Hospital Map Page** using `google_maps_flutter`
- Fetches user's **real-time GPS location** via `geolocator`
- Queries the **OpenStreetMap Overpass API** (no API key required) for hospitals within 5km
- Displays all nearby hospitals as **map markers** with names and info windows
- **Dark mode map style** matches the app's overall dark theme
- Floating action buttons to:
  - Re-center map to current location
  - Refresh hospital markers

### 5. 🎨 UI/UX Design
- **Dark / Light theme toggle** available throughout the app
- **Glassmorphism-style AppBar** (blur + transparency effect)
- Smooth UI animations on auth pages and main screen
- **120Hz / high refresh rate** support enabled on compatible Android devices
- Edge-to-edge display (no system nav bar overlap)
- Custom **app icon** configured for Android, iOS, Web, Windows, macOS

### 6. ☁️ Cloud & Storage
- **Firebase** integration for secure cloud document storage
- Medical records stored per user profile
- Designed for medical data confidentiality

---

## 📂 Project File Structure

```
medi_agent/
│
├── lib/
│   ├── main.dart         # Main app, AI chat UI, report upload, theme management
│   ├── auth_pages.dart   # Login, Sign-Up, Google Sign-In screens
│   └── map_page.dart     # GPS hospital finder with Google Maps
│
├── main.py               # Python FastAPI AI backend (Gemini integration)
├── pubspec.yaml          # Flutter dependencies & app config (v2.1.0)
├── app_icon.png          # Custom launcher icon
├── android/              # Android-specific configuration
├── ios/                  # iOS-specific configuration
└── README.md             # Project overview
```

---

## 📦 Key Flutter Dependencies

| Package | Purpose |
|---|---|
| `google_sign_in ^6.2.1` | Google OAuth authentication |
| `google_maps_flutter ^2.5.3` | Interactive map display |
| `geolocator ^14.0.2` | Real-time GPS location |
| `image_picker ^1.2.1` | Upload medical report images |
| `flutter_markdown ^0.7.7` | Render AI responses as formatted text |
| `shared_preferences ^2.2.2` | Persistent local storage (login state) |
| `flutter_displaymode ^0.6.0` | 120Hz high refresh rate on Android |
| `http ^1.6.0` | API requests to backend |

---

## 📈 Commit History Summary

| Date | Change |
|---|---|
| Feb 2026 | 🚀 First commit — project initialized |
| Feb 2026 | 📄 README written with full project details |
| Mar 2026 | 🖼️ iOS app icons added (72×72 @1x, @2x) |
| Mar 2026 | 🌐 API endpoints updated to production URLs |
| Apr 1, 2026 | 🔐 Google Sign-In + Auth pages implemented |
| Apr 1, 2026 | 🐛 Timeout handling added for API cold starts |
| Apr 2, 2026 | 📦 Package versions updated |
| Apr 5, 2026 | 🔢 Version bumped to 2.1.0+1 |
| Apr 14, 2026 | 🗺️ Main app + location services initialized |
| Apr 14, 2026 | 🔐 Auth pages enhanced and re-implemented |
| Apr 28, 2026 | 🗺️ Google Maps hospital finder integrated |
| Apr 28, 2026 | ✨ UI animations and Snackbar styling improved |
| Apr 30, 2026 | 👋 Dynamic greeting based on login status |
| Apr 30, 2026 | ♻️ Backend warm-up call removed (cleaner startup) |
| Apr 30, 2026 | ⏱️ Timeout handling added to all server requests |

---

## 🔮 Planned Future Features

- [ ] Hospital appointment booking system
- [ ] Hospital EMR (Electronic Medical Records) integration
- [ ] Health risk prediction model
- [ ] Video consultation support
- [ ] Wearable device data integration (e.g., smartwatch health data)

---

## 🎓 Project Purpose

MediAgent was developed to:
1. **Reduce patient confusion** when reading complex medical reports
2. **Improve access** to the right healthcare professional faster
3. **Leverage AI automation** to democratize medical literacy

---

*MediAgent — Empowering patients with AI-driven medical clarity* 🩺
