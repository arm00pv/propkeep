# PROPKEEP — AI Property Management Compliance Expert

![Flutter](https://img.shields.io/badge/Flutter-3.44-blue)
![Android](https://img.shields.io/badge/Android-12%2B-green)
![iOS](https://img.shields.io/badge/iOS-15%2B-blue)
![License](https://img.shields.io/badge/License-MIT-yellow)

## What is PROPKEEP?

PROPKEEP is an AI-powered property management compliance expert that helps landlords and property managers navigate landlord-tenant law across all 50 US states + federal regulations.

The app uses **RAG (Retrieval-Augmented Generation)** with an Ollama LLM and a knowledge base of 316 Q&A pairs, 24 federal law facts, 51 state compliance profiles, and 8 real-world compliance scenarios to provide expert-level answers to property management questions.

## Features

### 🏠 Chat — Ask the AI Brain
- Ask any property management or landlord-tenant question
- Auto-detects which US state you're asking about
- RAG-powered answers grounded in real law
- Quick question chips for common topics
- Chat history saved locally on device

### 📋 States — 50-State Compliance Lookup
- Tap any state for instant compliance facts:
  - Security deposit limits
  - Deposit return deadlines (days)
  - Notice to vacate requirements
  - Eviction notice timelines
  - Rent control status

### ⚠️ Scenarios — Real-World Compliance
- 8 real-world compliance scenarios with:
  - ✅ Correct action
  - ❌ Common mistake
  - 💰 Penalty if wrong

## Architecture

```
Flutter App (Android/iOS)
    ↓
Django REST API
    ↓
PROPKEEP Brain (RAG + Ollama LLM)
    ↓
Knowledge Base (316 Q&A + 24 federal facts + 51 states + 8 scenarios)
```

### On-Device AI (Planned)
The app will support `flutter_litert_lm` and `google_ai_edge` SDK for on-device LLM inference, enabling:
- Offline mode (no internet required)
- Privacy (legal data never leaves the phone)
- Zero API costs

## Version Support

| Platform | Min Version | Max Version |
|----------|-------------|-------------|
| Android | 12 (API 31) | 15 (API 35) |
| iOS | 15.0 | 18.x |

## Build

### Flutter App
```bash
cd app/flutter
flutter pub get
flutter build apk --release    # Android APK
flutter build appbundle --release  # Android AAB (Play Store)
flutter build ios --release    # iOS (requires macOS + Xcode)
```

### Backend API
```bash
# Start Django server
cd /path/to/failover-platform/control_plane
python3 manage.py runserver 0.0.0.0:8000
```

### Training Data
```bash
# Generate training data (50 states + federal law)
python3 src/build_training_data.py

# Train Mamba-3 LoRA brain (optional, RAG is primary)
python3 src/train_brain.py
```

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Mobile App | Flutter 3.44 (Dart) |
| Backend API | Django REST Framework |
| AI Brain | Ollama LLM (qwen3.5:9b) + RAG |
| Knowledge Base | JSON (316 Q&A + 279 facts + 8 scenarios) |
| Mamba Brain | Custom Mamba-3 SSM with LoRA adapter |
| State Detection | NLP keyword matching + state abbreviation parsing |

## Knowledge Base Coverage

### Federal Law
- Fair Housing Act (7 protected classes, accommodations, ESA)
- Lead-Based Paint Hazard Reduction Act (pre-1978 disclosure)
- ADA compliance for rental properties
- Implied warranty of habitability
- FCRA tenant screening requirements
- Eviction due process (no self-help evictions)

### State Law (All 50 + DC)
- Security deposit limits
- Deposit return deadlines
- Notice to vacate requirements
- Eviction notice timelines
- Rent control status
- Late fee regulations

### Compliance Scenarios
- Emotional support animal requests
- Self-help eviction (illegal in all 50 states)
- Lead paint disclosure failures
- Disability accommodation requests
- Rent increase procedures
- Security deposit deductions

## License

MIT License — see LICENSE file for details