# Roland V-160HD App - Handoff Document

## Project Overview
Flutter app to control a Roland V-160HD video switcher via TCP/IP (Telnet protocol on port 8023).

## Current State: WORKING

### What's Working
- App builds and runs on macOS (`flutter run -d macos`)
- Network connection established (Mac mini Ethernet → Roland switch port 5 or 6)
- Mac static IP: `10.0.1.100`, Roland IP: `10.0.1.20`
- Telnet negotiation works
- Password authentication works (password: `0000`)
- App auto-connects on startup
- UI shows connection status
- **All button commands work** (CUT, AUTO, PGM, PST, etc.)

## Key Files
- `lib/main.dart` - UI, auto-connect logic
- `lib/services/roland_service.dart` - Connection, commands, response handling

## Changes Made

### Network Configuration
- Problem: iPad on building WiFi, Roland on isolated network
- Solution: Connected Mac mini Ethernet to Roland's switch
- Had to use Gigabit port (5 or 6) on switch — PoE ports didn't work with Mac
- Set static IP on Mac: 10.0.1.100 (Roland is at 10.0.1.20)

### macOS App Fixes
- Added network.client entitlement to allow outgoing connections (was getting "Operation not permitted")
- Files changed: `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`

### Roland Authentication
- Discovered: Roland uses Telnet protocol with password authentication
- Password is `0000`
- Updated RolandService to:
  - Handle Telnet negotiation (0xFF bytes)
  - Send password after connecting
  - Wait for "Welcome" response
- Added `password` parameter to constructor (defaults to `'0000'`)
- Fixed UTF-8 decode error with `allowMalformed: true`

### UI Improvements
- Changed default IP to `10.0.1.20`
- Added auto-connect on app start
- Added connecting spinner
- Added error message display if connection fails

### Command Timeout Fix (Final Fix)
**Problem:** Commands were sent but timed out waiting for ACK responses.

**Root Causes Found:**
1. Commands were sent without line terminators - Roland requires `\r\n` after each command
2. Roland prefixes responses with STX (`\x02`) which wasn't being stripped, so `ACK;` wasn't recognized

**Fixes Applied in `lib/services/roland_service.dart`:**

1. **Added CR+LF line terminator to commands** (line ~1513 in `_processQueue`):
   ```dart
   _socket!.write('$cmd\r\n');  // Add CR+LF terminator
   ```

2. **Strip STX character from responses** (line ~1522 in `_handleResponse`):
   ```dart
   String cleaned = data.replaceAll('\r', '').replaceAll('\x02', '');
   ```

## Roland Protocol Notes
- Port: 8023 (Telnet)
- Commands end with `;` and require `\r\n` line terminator
- Responses prefixed with `\x02` (STX), end with `ACK;` or `NACK;`
- Example: Send `CUT;\r\n` → Receive `\x02ACK;\n`

## How to Test
1. Run app: `flutter run -d macos`
2. App should auto-connect to `10.0.1.20`
3. Press CUT or AUTO button - should work immediately
4. Check terminal for any errors

## Environment
- Mac mini M1 2020, macOS Sonoma 14.8.1
- Flutter 3.38.5
- Roland V-160HD firmware 3.41.312
