# HackUMass Camera App - Complete Setup Guide

This guide will walk you through setting up the development environment and running the HackUMass Camera App with remote camera sharing features.

## Table of Contents
1. [Install Flutter](#1-install-flutter)
2. [Install Android Studio](#2-install-android-studio)
3. [Install Node.js](#3-install-nodejs)
4. [Setup the Project](#4-setup-the-project)
5. [Run the Signaling Server](#5-run-the-signaling-server)
6. [Run the Flutter App](#6-run-the-flutter-app)
7. [Testing](#7-testing)

---

## 1. Install Flutter

### Windows

1. **Download Flutter SDK**
   - Go to: https://docs.flutter.dev/get-started/install/windows
   - Download the Flutter SDK zip file
   - Extract to `C:\src\flutter` (or your preferred location)

2. **Add Flutter to PATH**
   - Open "Edit environment variables for your account"
   - Under "User variables", find "Path"
   - Click "Edit" → "New"
   - Add: `C:\src\flutter\bin`
   - Click "OK" to save

3. **Verify Installation**
   ```bash
   flutter doctor
   ```

### macOS

1. **Download Flutter SDK**
   ```bash
   cd ~/development
   curl -O https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_3.x.x-stable.zip
   unzip flutter_macos_3.x.x-stable.zip
   ```

2. **Add Flutter to PATH**
   ```bash
   echo 'export PATH="$PATH:$HOME/development/flutter/bin"' >> ~/.zshrc
   source ~/.zshrc
   ```

3. **Verify Installation**
   ```bash
   flutter doctor
   ```

### Linux

1. **Download and Extract**
   ```bash
   cd ~/development
   wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.x.x-stable.tar.xz
   tar xf flutter_linux_3.x.x-stable.tar.xz
   ```

2. **Add to PATH**
   ```bash
   echo 'export PATH="$PATH:$HOME/development/flutter/bin"' >> ~/.bashrc
   source ~/.bashrc
   ```

3. **Verify Installation**
   ```bash
   flutter doctor
   ```

---

## 2. Install Android Studio

### All Platforms

1. **Download Android Studio**
   - Go to: https://developer.android.com/studio
   - Download for your platform
   - Install following the wizard

2. **Install Android SDK**
   - Open Android Studio
   - Go to: Tools → SDK Manager
   - Install:
     - Android SDK Platform-Tools
     - Android SDK Build-Tools
     - Android 13.0 (API 33) or higher

3. **Install Flutter Plugin**
   - Go to: File → Settings → Plugins (Windows/Linux)
   - Or: Android Studio → Preferences → Plugins (macOS)
   - Search for "Flutter"
   - Click "Install"
   - Restart Android Studio

4. **Accept Android Licenses**
   ```bash
   flutter doctor --android-licenses
   ```
   Type 'y' to accept all licenses

---

## 3. Install Node.js

### Windows

1. **Download Node.js**
   - Go to: https://nodejs.org/
   - Download LTS version (v18 or higher)
   - Run installer
   - Follow installation wizard

2. **Verify Installation**
   ```bash
   node --version
   npm --version
   ```

### macOS

**Using Homebrew:**
```bash
brew install node
```

**Or download from:**
- https://nodejs.org/

**Verify:**
```bash
node --version
npm --version
```

### Linux

**Ubuntu/Debian:**
```bash
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs
```

**Verify:**
```bash
node --version
npm --version
```

---

## 4. Setup the Project

### Clone or Navigate to Project

```bash
cd C:\Users\DELL\OneDrive\Desktop\HackUMass_codebase
```

### Install Flutter Dependencies

```bash
flutter pub get
```

This will download all required Flutter packages:
- flutter_webrtc
- socket_io_client
- camera
- permission_handler
- image_picker
- google_generative_ai
- path_provider

### Install Signaling Server Dependencies

```bash
cd signaling-server
npm install
cd ..
```

This installs:
- express
- socket.io
- cors

---

## 5. Run the Signaling Server

### Start the Server

```bash
cd signaling-server
npm start
```

You should see:
```
Signaling server running on port 3000
Health check available at http://localhost:3000/health
```

### Test the Server

Open a new terminal and run:
```bash
curl http://localhost:3000/health
```

Expected response:
```json
{"status":"ok","activeSessions":0,"uptime":...}
```

### Keep Server Running

**Important:** Keep this terminal window open while testing the app. The server must be running for remote camera features to work.

---

## 6. Run the Flutter App

### Option A: Using Android Emulator

1. **Create an Emulator (if needed)**
   - Open Android Studio
   - Tools → Device Manager
   - Click "Create Device"
   - Select a phone (e.g., Pixel 5)
   - Select system image (API 33 or higher)
   - Finish setup

2. **Start the Emulator**
   - In Device Manager, click the play button next to your emulator

3. **Run the App**
   ```bash
   flutter run
   ```

### Option B: Using Physical Android Device

1. **Enable Developer Options**
   - Go to Settings → About Phone
   - Tap "Build Number" 7 times
   - Go back to Settings → Developer Options
   - Enable "USB Debugging"

2. **Connect Device**
   - Connect phone via USB
   - Allow USB debugging when prompted

3. **Verify Connection**
   ```bash
   flutter devices
   ```

4. **Run the App**
   ```bash
   flutter run
   ```

### Option C: Using iOS Simulator (macOS only)

1. **Install Xcode**
   - Download from Mac App Store
   - Open Xcode and accept license

2. **Install CocoaPods**
   ```bash
   sudo gem install cocoapods
   ```

3. **Run the App**
   ```bash
   flutter run -d ios
   ```

---

## 7. Testing

### Test Local Camera Feature

1. Launch the app
2. Tap "Open Local Camera"
3. Take a photo
4. Tap "Describe Image"
5. View AI-generated description

### Test Remote Camera Sharing

**You need TWO devices for this test:**

#### Device 1 (Sender):
1. Launch the app
2. Tap "Share Camera"
3. Grant camera and microphone permissions
4. Note the 6-character pairing code displayed

#### Device 2 (Receiver):
1. Launch the app
2. Tap "Connect"
3. Enter the pairing code from Device 1
4. Tap "Connect"
5. You should see Device 1's camera feed

#### Test Features:
- On Device 1: Tap "Switch Camera" to toggle front/back
- On Device 2: Tap "Capture" (coming soon)
- Either device: Tap disconnect to end session

### Testing on Same Computer

If you only have one physical device:

1. **Run app on physical device**
2. **Run app on emulator**
3. **Update server URL on physical device:**
   - Find your computer's local IP:
     - Windows: `ipconfig` (look for IPv4 Address)
     - Mac/Linux: `ifconfig` (look for inet)
   - Update `_serverUrl` in `lib/main.dart` to `http://YOUR_IP:3000`
   - Rebuild the app

---

## Common Issues and Solutions

### Flutter Doctor Issues

**Issue:** "Android toolchain - develop for Android devices" has issues

**Solution:**
```bash
flutter doctor --android-licenses
```

**Issue:** "cmdline-tools component is missing"

**Solution:**
- Open Android Studio → SDK Manager
- SDK Tools tab → Check "Android SDK Command-line Tools"
- Click Apply

### Signaling Server Issues

**Issue:** "Port 3000 already in use"

**Solution:**
```bash
PORT=3001 npm start
```
Then update `_serverUrl` in the app to use port 3001

**Issue:** "Cannot connect to server from physical device"

**Solution:**
- Ensure phone and computer are on same WiFi network
- Use computer's local IP instead of localhost
- Check firewall allows connections on port 3000

### App Build Issues

**Issue:** "Gradle build failed"

**Solution:**
```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
flutter run
```

**Issue:** "CocoaPods not installed" (iOS)

**Solution:**
```bash
sudo gem install cocoapods
cd ios
pod install
cd ..
flutter run
```

### Permission Issues

**Issue:** Camera/microphone not working

**Solution:**
- Check app permissions in device settings
- Uninstall and reinstall the app
- Grant permissions when prompted

---

## Network Configuration

### For Local Testing (Same WiFi)

1. Find your computer's IP address:
   - Windows: `ipconfig`
   - Mac/Linux: `ifconfig` or `ip addr`

2. Update `lib/main.dart`:
   ```dart
   static const String _serverUrl = 'http://192.168.1.XXX:3000';
   ```

3. Rebuild the app:
   ```bash
   flutter run
   ```

### For Internet Testing

1. Deploy signaling server to cloud (Heroku, AWS, etc.)
2. Update `_serverUrl` to your server's public URL
3. Ensure server uses HTTPS/WSS in production

---

## Next Steps

Once everything is working:

1. **Customize the app:**
   - Update app name in `pubspec.yaml`
   - Change app icon
   - Modify theme colors

2. **Deploy signaling server:**
   - See `signaling-server/README.md` for deployment options

3. **Build release version:**
   ```bash
   flutter build apk --release  # Android
   flutter build ios --release  # iOS
   ```

---

## Getting Help

If you encounter issues:

1. Check `flutter doctor` output
2. Review signaling server logs
3. Check Flutter console for errors
4. Ensure all prerequisites are installed
5. Verify network connectivity

For more help, see the main README.md troubleshooting section.
