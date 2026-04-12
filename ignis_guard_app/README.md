# ignis_guard_app

IgnisGuard - A Flutter application for monitoring gas levels, temperature, humidity, and location images.

## Getting Started

### Prerequisites
- Flutter SDK
- Firebase account and project

### Setup

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd ignis_guard_app
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase**
   - Copy `.env.example` to `.env`:
     ```bash
     cp .env.example .env
     ```
   - Open `.env` and fill in your Firebase credentials from your Firebase Console
   - Get these values from: https://console.firebase.google.com/

4. **Run the app**
   ```bash
   flutter run
   ```

## Environment Variables

This project uses environment variables to store sensitive information like Firebase API keys. 

**Important:** Never commit the `.env` file to version control. The `.env.example` file is provided as a template.

### Required Environment Variables

- `FIREBASE_API_KEY` - Your Firebase API key
- `FIREBASE_PROJECT_ID` - Your Firebase project ID
- `FIREBASE_APP_ID` - Your Firebase app ID
- `FIREBASE_MESSAGING_SENDER_ID` - Firebase messaging sender ID
- `FIREBASE_STORAGE_BUCKET` - Firebase storage bucket
- `FIREBASE_DATABASE_URL` - Firebase database URL

## Features

- Real-time gas level monitoring
- Temperature tracking
- Humidity monitoring
- Last captured image display
- Alert system for dangerous conditions

## Resources

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
