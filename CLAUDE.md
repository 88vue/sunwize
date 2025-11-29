# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Sunwize** is an iOS SwiftUI app that provides intelligent UV exposure tracking and skin health monitoring. The app uses advanced indoor/outdoor/vehicle detection powered by GPS accuracy patterns, polygon-based geofencing, and motion sensors to automatically track UV exposure only when users are genuinely outdoors.

**Key Features**:
- Real-time UV exposure tracking with automatic indoor/outdoor detection
- Vitamin D synthesis estimation based on body exposure and UV index
- Body scan tracking with 3D visualization for monitoring skin spots (ABCDE criteria)
- Streak tracking for UV safety and vitamin D goals
- Background location monitoring with iOS native geofencing

**Tech Stack**: SwiftUI, CoreLocation, CoreMotion, Supabase (auth + database), OpenStreetMap (building data)

## Building and Running

### Prerequisites
- Xcode 15+
- iOS 17+ deployment target
- Supabase account with configured database (see `supabase_schema.sql`)

### Build Commands
```bash
# Build for simulator
xcodebuild -scheme sunwize -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 15' build

# Clean build
xcodebuild -scheme sunwize -sdk iphonesimulator clean build

# Build for device (requires signing)
xcodebuild -scheme sunwize -sdk iphoneos build
```

### Environment Configuration

**Required**: Create `Info.plist.example` or set environment variables:
- `SUPABASE_URL`: Your Supabase project URL
- `SUPABASE_ANON_KEY`: Your Supabase anonymous key

**Database Setup**: Run `supabase_schema.sql` in your Supabase SQL Editor to create tables.

### Testing Locations

The app includes extensive logging for debugging indoor/outdoor/vehicle detection. Look for these log prefixes:
- `🎯 DETECTION RESULT`: Final classification with confidence
- `📊 Accuracy pattern`: GPS pattern analysis
- `🏢 Inside polygon`: Building boundary detection
- `🪟 NEAR WINDOW detected`: False positive prevention
- `🔒 OUTDOOR LOCK`: UV tracking state machine
- `🚗🔒 Vehicle lock ACTIVATED`: Vehicle tracking lock engaged (Phase 1)
- `🚗🔓 Vehicle lock RELEASED`: Vehicle tracking lock released (parking detected)
- `🅿️ Parking detected`: Definitive parking confirmation (3+ min stationary)
- `🚦 Stop-and-go detected`: City driving pattern recognition

## Core Architecture

### 1. Indoor/Outdoor Detection System

**Location**: `sunwize/Services/Location/LocationManager.swift` (3000+ lines)

**Critical Concept**: Three-tier state machine prevents false positives while maintaining accuracy.

**Tier 1 - Starting UV Tracking** (Very Conservative):
- Requires 0.90 confidence (0.92 during startup)
- Absolute veto if inside building polygon
- Distance >40m from buildings OR recent polygon exit OR clear outdoor evidence
- Activates "outdoor tracking lock" 🔒

**Tier 2 - Maintaining UV Tracking** (Stable & Sticky):
- Ignores distance oscillations and confidence variations
- Only exits on strong indoor signals (polygon occupancy >30s, floor detection, vehicle)
- Prevents flip-flopping when walking past buildings

**Tier 3 - Stopping UV Tracking** (Responsive to Strong Signals):
- When locked: Requires sustained polygon occupancy, floor detection, or vehicle (0.85+ confidence)
- When not locked: Requires 0.70 confidence

**Classification Signal Priority** (first match wins):
1. **Floor Detection** (0.95 confidence indoor) - Multi-story buildings
2. **Accuracy Pattern** (0.85 confidence) - GPS signature analysis (avg accuracy + std dev)
3. **Building Data + Polygon** - OpenStreetMap exact boundaries with movement-validated exits
4. **Motion/Vehicle** (0.80-0.90 confidence) - CoreMotion activity detection
5. **Fallback Heuristic** - When building data unavailable

**Near-Window False Positive Prevention** (Lines 1557-1567, 2548-2553, 2574-2579):
- Problem: Desk near window gets excellent GPS (5-15m) → system thinks "outdoor"
- Solution: If stationary >2min + excellent GPS + near/inside building → classify as UNKNOWN
- Prevents UV tracking indoors while preserving outdoor scenarios (bus stops, benches)

**Polygon-Based Geofencing** (Lines 710-793):
- Uses exact OSM building boundaries instead of 30m circular geofences
- **Movement validation**: Exits require ≥10m movement to prevent GPS drift false positives
- Entry: Records timestamp + GPS position
- Exit: Validates movement; rejects if <10m (GPS drift, not real exit)

**Circular Geofences** (Background wake-up only):
- Setup: 30m radius circles around nearest 20 buildings
- Purpose: Wake app from suspended state via iOS callbacks
- NOT used for classification (polygon-based is more accurate)

### 2. Background UV Tracking

**Location**: `sunwize/Services/Background/BackgroundTaskManager.swift`

**How it Works**:
- LocationManager continuously monitors location via iOS native background updates
- Every location update → `handleLocationUpdate()` evaluates outdoor state
- If outdoor confirmed (0.90 confidence) + lock not active → start UV tracking + activate lock
- While locked → update UV exposure every 30-60s (faster for high UV)
- Strong indoor signal → stop tracking + release lock

**Background Tasks**:
- `com.sunwize.uvtracking`: Location-based UV exposure updates
- `com.sunwize.dailymaintenance`: Daily streak calculations
- `com.sunwize.apprefresh`: Periodic data sync

**Confidence Thresholds**:
- Start outdoor tracking: 0.90 (0.92 during startup)
- Stop outdoor tracking (not locked): 0.70
- Stop outdoor tracking (locked): Strong signal required (sustained polygon, floor, vehicle)
- Vehicle detection: 0.85 (immediate stop, safety critical)

### 3. Vehicle Detection System (Phase 1 Improvements - Nov 2025)

**Location**: `sunwize/Services/Location/LocationManager.swift` (lines 1984-2204) + `BackgroundTaskManager.swift` (lines 703-911)

**Critical Concept**: Vehicle mode now uses tracking lock system (symmetric with outdoor lock) to prevent flip-flopping during stop-and-go city driving.

#### **Problem Solved** (Pre-Phase 1):
- Vehicle detected briefly → stops UV tracking → releases outdoor lock
- Next update at red light → reclassifies as "outside" → **UV tracking resumes in car** ❌
- Caused by: No vehicle lock + 2-minute persistence window too short + threshold mismatch (0.7 vs 0.85)

#### **Phase 1 Fix #1: Aligned Confidence Thresholds** (`LocationManager.swift:2199`)
**Changed**: `isVehicle` threshold from **0.7 → 0.80**
- **Why**: Eliminates oscillation where borderline detections (0.72-0.78) trigger but get rejected by BackgroundTaskManager (0.85 threshold)
- **Trade-off**: May miss very slow vehicle detection (parking lot crawl at 0.78), but eliminates flip-flopping
- **False Positive Risk**: LOW - more conservative threshold reduces cyclist/jogger false positives

#### **Phase 1 Fix #2: Vehicle Tracking Lock** (`BackgroundTaskManager.swift:91-98, 703-784, 871-911`) ⭐ **MOST CRITICAL**
**Added**: Symmetric lock system for vehicle mode (equivalent to outdoor tracking lock)

**How it Works**:
1. **Activation**: When vehicle detected with 0.85+ confidence → `isVehicleTrackingLocked = true`
2. **Maintenance**: While locked, **ignores all reclassification** to outdoor/indoor (prevents flip-flop)
3. **Release**: Only releases when parking definitively detected

**Parking Detection** (`isDefinitelyParked()`):
Requires **ALL** of:
- 3+ minutes since vehicle lock started
- No vehicle detection in last 2 minutes (no CoreMotion automotive activity)
- Current mode is indoor/unknown (stationary)
- Speed < 0.5 m/s (walking pace)
- **Exception**: If classified as outdoor with movement → likely walking away from parked car → release lock immediately

**Log Patterns**:
```
🚗🔒 [BackgroundTaskManager] Vehicle lock ACTIVATED (confidence: 0.88)
🚗🔒 [BackgroundTaskManager] Vehicle lock active (45s) - ignoring reclassification to outside
🅿️ [BackgroundTaskManager] Parking detected: 185s stationary, 125s since last vehicle detection
🚗🔓 [BackgroundTaskManager] Vehicle lock RELEASED (parking detected after 185s)
```

**Architecture Symmetry** (Fix #2):
| Feature | Outdoor Mode | Vehicle Mode |
|---------|-------------|--------------|
| **Sticky lock** | ✓ Outdoor tracking lock | ✓ Vehicle tracking lock (Phase 1) |
| **Persistence** | Until strong indoor signal | Until parking confirmed |
| **Weak signal handling** | Ignored while locked | Ignored while locked (Phase 1) |
| **Lock release condition** | Polygon entry/floor/vehicle | 3min stationary + no automotive |

**False Positive Risk**: VERY LOW - conservative 3-minute parking detection prevents premature release

#### **Phase 1 Fix #3: Extended Vehicle Persistence** (`LocationManager.swift:2003-2016`)
**Changed**: Persistence window from **2 minutes → 5 minutes** with slower confidence decay

**Before**:
- 120s persistence window
- 240s half-life decay (confidence drops quickly at stops)
- Vehicle mode lost after 2 minutes at red light

**After**:
- 300s persistence window (covers multiple traffic lights)
- 600s half-life decay (confidence maintained longer)
- Minimum confidence floor: 0.85 (was 0.88) to match BackgroundTaskManager threshold

**Why This Matters**:
- City driving stop-and-go: Long red lights (90-120 seconds) no longer expire vehicle mode
- CoreMotion `.automotive` often stops at red lights (engine idle) → persistence maintains vehicle state
- Works with Fix #2: Persistence refreshes `lastVehicleDetectionTime` → parking detection timer resets with movement

**False Positive Risk**: LOW-MEDIUM when used alone, but **mitigated by Fix #2** (vehicle lock + parking detection)

#### **Vehicle Detection Tiers** (Unchanged, Reference Only)

**TIER 0: Vehicle Mode Persistence** (Lines 1988-2017)
- If vehicle detected recently, maintain through brief stops (up to 5 min)
- Stop-and-go pattern detection: Stopped but was recently moving fast → maintain vehicle mode
- Parking detection: 5+ minutes stationary + no automotive → exit vehicle mode

**TIER 1: CoreMotion Automotive Activity** (Lines 2019-2053) - HIGHEST PRIORITY
- iOS accelerometer detects vehicle motion patterns (acceleration/braking)
- 50%+ automotive samples → 0.95 confidence
- Automotive + moderate speed (>3 m/s) → 0.90 confidence
- Automotive even when stopped (engine vibrations) → 0.85 confidence

**TIER 2: GPS Speed-Based Detection** (Lines 2055-2133)
- Highway (>50 mph): 0.98 confidence
- Fast city (25+ mph): 0.92 confidence
- Moderate city (13+ mph): 0.88 confidence
- Slow city (9+ mph): 0.82 confidence
- **Cyclist exclusion**: Fast cyclists (6+ m/s) NOT classified as vehicle

**TIER 3: Stop-and-Go Pattern Detection** (Lines 2158-2177)
- High speed variance (std dev >2.5 m/s) + moderate avg speed + peaks >8 m/s
- Characteristic of city driving with traffic lights
- 0.85 confidence

#### **Testing Vehicle Detection (Post Phase 1)**

**Expected Behavior**:
1. **Highway driving**: Detects within 10-15 seconds (high speed → 0.98 confidence)
2. **City driving**: Detects within 20-30 seconds (moderate speed → 0.88 confidence + lock activates)
3. **Stop-and-go**: Lock maintains vehicle state through red lights (ignores outdoor reclassification)
4. **Parking**: Lock releases after 3 minutes stationary OR immediate release if walking away

**Debug Log Patterns**:
```
# Initial detection
🚗 VEHICLE (CoreMotion): 60% automotive samples - HIGH CONFIDENCE
🚗🔒 [BackgroundTaskManager] Vehicle lock ACTIVATED (confidence: 0.90)

# During stop-and-go
🚦 [LocationManager] Stop-and-go detected (#3): currently stopped but was moving at 9.2 m/s
🚗🔒 [BackgroundTaskManager] Vehicle lock active (78s) - ignoring reclassification to outside

# Parking detection (stationary)
🅿️ [BackgroundTaskManager] Parking detected: 192s stationary, 135s since last vehicle detection
🚗🔓 [BackgroundTaskManager] Vehicle lock RELEASED (parking detected after 192s)

# Parking detection (walking away)
🚶 [BackgroundTaskManager] Outdoor movement detected after vehicle lock - likely exited parked vehicle
🚗🔓 [BackgroundTaskManager] Vehicle lock RELEASED (parking detected after 95s)
```

**Common Issues (Now Fixed)**:
- ❌ **Pre-Phase 1**: "Vehicle detected very briefly then switches to outside" → **FIXED by vehicle lock**
- ❌ **Pre-Phase 1**: "UV tracking resumes while sitting in car at red light" → **FIXED by lock ignoring reclassification**
- ❌ **Pre-Phase 1**: "Vehicle mode lost after 2-minute red light" → **FIXED by 5-minute persistence**

### 4. Data Architecture

**Database**: Supabase PostgreSQL with Row Level Security

**Key Models** (all in `sunwize/Models/Database/`):
- `Profile`: User settings (age, gender, skin type, MED)
- `UVSession`: UV exposure sessions with start/end times, session SED
- `VitaminDData`: Daily vitamin D synthesis tracking
- `BodyLocation` + `BodySpot`: 3D body spot coordinates + spot metadata (ABCDE criteria)
- `Streaks`: UV safety and vitamin D goal tracking

**Date Handling Critical Fix** (`SupabaseManager.swift` lines 20-51):
- Database `DATE` columns return "2025-11-11" (date-only, no time)
- Database `TIMESTAMPTZ` columns return "2025-11-11T10:30:00Z"
- Custom decoder handles BOTH formats to prevent "Invalid date format" errors
- All GET requests use: `let data = try SupabaseManager.customDecoder.decode([Model].self, from: response.data)`

### 4. UV Calculations

**Location**: `sunwize/Utilities/Calculations/UVCalculations.swift`

**Standard Erythema Dose (SED)**: 100 J/m² of UV radiation

**Formula**: `SED = (UV_Index × Body_Exposure_Factor × Time_Minutes) / 100`

**Minimal Erythema Dose (MED)**: Skin-type specific threshold:
- Skin Type I (pale): 200-300 SED
- Skin Type II (fair): 250-350 SED
- Skin Type III (medium): 300-450 SED
- Skin Type IV-VI (dark): 450-600+ SED

**Vitamin D Synthesis**: `IU = SED × Body_SA × Efficiency × Conversion_Factor`
- Body surface area varies by age/gender
- Efficiency decreases with higher vitamin D levels
- SPF sunscreen reduces synthesis by ~95%

### 5. Services Layer

**AuthenticationService** (`sunwize/Services/AuthenticationService.swift`):
- Manages Supabase auth + profile CRUD
- Initializes location tracking after successful login/onboarding
- Singleton shared instance

**LocationManager** (`sunwize/Services/Location/LocationManager.swift`):
- **THE CORE** of the app - 3000+ lines of detection logic
- See "Indoor/Outdoor Detection System" above
- Singleton shared instance, @MainActor isolated

**WeatherService** (`sunwize/Services/API/WeatherService.swift`):
- Fetches UV index from currentuvindex.com (no API key required)
- Sun times from sunrisesunset.io
- Thread-safe cache with barrier dispatch queue (fixed EXC_BAD_ACCESS crash)

**OverpassService** (`sunwize/Services/Location/OverpassService.swift`):
- Queries OpenStreetMap for building polygons within radius
- Returns exact lat/lon coordinates for polygon boundaries
- Used by LocationManager for point-in-polygon checks

**SupabaseManager** (`sunwize/Services/Database/SupabaseManager.swift`):
- Centralized database operations
- Custom date decoder for DATE vs TIMESTAMPTZ handling
- All CRUD operations with Row Level Security

**NotificationManager** (`sunwize/Services/NotificationManager.swift`):
- UV warning/danger notifications when approaching MED threshold
- Vitamin D Target Reached Notification
- Morning Notification with the peak UV time for the day
- Body Spot Tracker notification sent once a month
- Cooldown period to prevent spam

**DaytimeService** (`sunwize/Services/DaytimeService.swift`):
- Determines if currently daytime (between sunrise/sunset)
- UV tracking only active during daytime

### 6. ViewModels

**ProfileViewModel**: User profile management + onboarding flow
**BodySpotViewModel**: 3D body model + spot tracking
**UVTrackingViewModel**: UV session management + vitamin D calculations

## Critical Implementation Notes

### Date Handling in Supabase Operations

**Always use the custom decoder for GET requests**:
```swift
let response = try await client.from("table").select().execute()
let data = try SupabaseManager.customDecoder.decode([Model].self, from: response.data)
```

**For INSERT/UPDATE, pass models directly** (SDK handles encoding):
```swift
try await client.from("table").insert(model).execute()
```

### Near-Window False Positive Prevention

When modifying location detection logic, preserve the near-window checks:
- Lines 1557-1567: Building distance classification veto
- Lines 2548-2553: Accuracy pattern polygon veto
- Lines 2574-2579: Accuracy pattern stationary veto

**The pattern**: Stationary >2min + excellent GPS (<15m) + near building (<5m) = UNKNOWN (not outdoor)

### Polygon Exit Movement Validation

**Never skip this check** (lines 800-817 in LocationManager.swift):
```swift
let movementDistance = haversineDistance(from: entryPosition, to: coordinate)
if movementDistance < 10 {
    // GPS drift, not real exit - REJECT
    return
}
```

Without this, GPS drift creates false polygon exits → indoor UV tracking.

### Outdoor Tracking Lock

Once activated, the outdoor lock persists until a **strong indoor signal**:
- Sustained polygon occupancy (>30s)
- Floor detection
- Vehicle detection (0.85+ confidence)
- Stationary near building >3min

**Do not** add logic that breaks the lock on weak signals (distance oscillations, temporary low confidence).

### Background Location Permissions

App requires "Always Allow" location permission for background UV tracking:
- Requested during onboarding (PermissionsView)
- User can downgrade to "When In Use" but background tracking stops
- Check `CLLocationManager.authorizationStatus()` before background operations

## Code Patterns

### Logging System

**DetectionLogger** (`sunwize/Utilities/DetectionLogger.swift`):
- Structured logging with categories and levels
- Categories: detection, signal, motion, transition, geofence, performance, state, uvTracking
- Use for all location detection related logs

```swift
DetectionLogger.logDetection(
    mode: .outside,
    confidence: 0.85,
    source: "accuracyPattern",
    coordinate: location.coordinate,
    accuracy: location.horizontalAccuracy,
    motion: "stationary",
    nearestBuilding: 50.0
)
```

### Geometry Utilities

**GeometryUtils** (`sunwize/Utils/GeometryUtils.swift`):
- `haversineDistance()`: Accurate distance between coordinates
- `pointInPolygon()`: Ray casting algorithm for polygon occupancy
- `nearestBuildingDistance()`: Distance to closest building boundary
- `distanceToPolygon()`: Minimum distance to polygon edge

### State Management

All major services use singleton pattern with `@MainActor` isolation:
```swift
@MainActor
class ServiceName: ObservableObject {
    static let shared = ServiceName()
    private init() {}
}
```

Views inject via `@EnvironmentObject` or access `.shared` directly.

## Common Gotchas

1. **Building data cache**: OpenStreetMap queries are cached for 5 minutes. Clear cache to test polygon detection: `LocationManager.shared.buildingCache.removeAll()`

2. **Startup phase**: First 2 minutes require higher confidence (0.92 vs 0.90). Set `isInStartupPhase = false` to test normal thresholds immediately.

3. **Motion activity**: Requires motion permission. Without it, `motion.isStationary` always false, affecting detection accuracy.

4. **Simulator vs Device**: GPS accuracy patterns differ significantly. Simulator often shows perfect accuracy; device near window shows realistic 5-15m.

5. **Background refresh**: iOS limits background execution. Use "Simulate Background Fetch" in Xcode or wait for actual location changes to trigger updates.

6. **Supabase RLS**: Row Level Security policies require `auth.uid()` to match user_id. Test with actual authenticated users, not direct SQL queries.

## Performance Considerations

- **Location updates**: Filtered by 15m distance (line 441 in LocationManager) to reduce unnecessary processing
- **Accuracy history**: Limited to last 50 samples to prevent memory growth
- **Building cache**: Spatial indexing with lat/lon keys rounded to ~100m precision
- **OpenStreetMap queries**: Limited to 200m radius, cached for 5 minutes
- **WeatherService cache**: Thread-safe with barrier writes to prevent race conditions

## File Organization

```
sunwize/
├── Config/           - AppConfig with API URLs and thresholds
├── Models/
│   ├── API/         - Weather API response models
│   ├── Auth/        - Auth models
│   └── Database/    - Supabase table models (Profile, UVSession, etc.)
├── Services/
│   ├── API/         - WeatherService, external APIs
│   ├── Background/  - BackgroundTaskManager (UV tracking orchestration)
│   ├── Database/    - SupabaseManager (centralized DB operations)
│   └── Location/    - LocationManager (THE CORE), OverpassService
├── Utilities/
│   └── Calculations/ - UVCalculations (SED, MED, Vitamin D formulas)
├── Utils/           - GeometryUtils (haversine, point-in-polygon)
├── ViewModels/      - ProfileVM, BodySpotVM, UVTrackingVM
└── Views/
    ├── Components/  - Reusable UI components
    ├── Main/        - Tab views (UV Tracking, Body Spot, Profile)
    └── Onboarding/  - Auth + permissions + setup flow
```

## Debugging Indoor/Outdoor Detection

**Enable verbose logging** (not currently implemented but should add):
```swift
DetectionLogger.isVerboseMode = true
DetectionLogger.enabledCategories = Set(DetectionLogger.Category.allCases)
```

**Key log patterns to watch**:
- `🎯 DETECTION RESULT`: Every location classification
- `📊 Accuracy pattern`: GPS signature (avg + std dev)
- `🏢 Inside polygon`: Building boundary checks
- `🪟 NEAR WINDOW detected`: False positive prevention triggered
- `🔒 OUTDOOR LOCK ACTIVATED`: UV tracking started
- `🔓 Strong indoor signal detected`: UV tracking stopped

**Common detection scenarios**:
- **Stationary outdoor** (park bench, bus stop): Requires >40m from building OR recent polygon exit
- **Urban sidewalk**: Walking + good GPS + high confidence ≥0.92
- **Near window indoors**: Should show "NEAR WINDOW detected" after 2min
- **Vehicle** (Phase 1): Should detect within 20-30s, lock activates, maintains through red lights
- **Building to building**: Polygon exit + walking should maintain outdoor state

## Testing Recommendations

1. **Real device testing is critical**: Simulator GPS doesn't match real-world patterns
2. **Test near windows**: Sit at desk for 5+ minutes, should NOT start UV tracking
3. **Test bus stop scenario**: Stand still outdoors 40m+ from buildings, should start within 2min
4. **Test polygon boundaries**: Walk in/out of buildings, check movement validation works
5. **Test urban sidewalks**: Walk between buildings <40m apart, should maintain outdoor with lock
6. **Test vehicle detection (Phase 1 improved)**:
   - **Highway driving**: Should detect within 10-15 seconds (high speed → 0.98 confidence)
   - **City driving**: Should detect within 20-30 seconds (0.88-0.92 confidence)
   - **Stop-and-go traffic**: Vehicle lock should maintain state through red lights (2-3 minutes)
   - **Parking**: Lock should release after 3 minutes stationary OR immediately when walking away
   - **Look for logs**: `🚗🔒 Vehicle lock ACTIVATED`, `🅿️ Parking detected`, `🚗🔓 Vehicle lock RELEASED`
7. **Test vehicle → parking → walking sequence**:
   - Drive around city (lock activates within 30s)
   - Park and stay in car for 3+ minutes (lock releases: `🅿️ Parking detected`)
   - Walk away from car (immediate lock release: `🚶 Outdoor movement detected`)
- always use this command for test building xcodebuild -scheme sunwize -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -30

## Recent Changes (Phase 1 - November 2025)

### Vehicle Detection System Overhaul

**Problem**: Vehicle mode was unstable during city driving, causing "brief vehicle detection → switches to outside" flip-flopping. This resulted in UV tracking incorrectly resuming while sitting in vehicles at red lights.

**Root Cause Analysis**:
1. No vehicle tracking lock (outdoor mode had lock, vehicle mode didn't)
2. Threshold mismatch: LocationManager declared vehicle at 0.7 confidence, BackgroundTaskManager required 0.85
3. 2-minute persistence window too short for stop-and-go city driving (long red lights expired vehicle mode)
4. Outdoor tracking lock released immediately when vehicle detected, but no equivalent protection maintained vehicle state

**Phase 1 Fixes Implemented**:

| Fix | File | Lines | Description | Risk |
|-----|------|-------|-------------|------|
| **#1: Threshold Alignment** | `LocationManager.swift` | 2199 | `isVehicle` threshold: 0.7 → 0.80 | LOW |
| **#2: Vehicle Tracking Lock** ⭐ | `BackgroundTaskManager.swift` | 91-98, 703-784, 871-911 | Added symmetric lock system for vehicle mode | VERY LOW |
| **#3: Extended Persistence** | `LocationManager.swift` | 2003-2016 | Persistence window: 2min → 5min, decay: 240s → 600s half-life | LOW-MEDIUM |

**Impact**:
- ✅ Eliminates flip-flopping between vehicle and outdoor modes
- ✅ Prevents UV tracking from resuming in vehicles (safety critical - windshield blocks UV)
- ✅ Maintains vehicle state through stop-and-go traffic (red lights, slow traffic)
- ✅ Conservative parking detection (3+ min) prevents false lock release
- ✅ Architecture symmetry: Both outdoor and vehicle modes now have sticky locks

**Testing Validation Required**:
- Real-world city driving with multiple traffic lights (2-5 minutes between movements)
- Parking detection: Stay in car 3+ minutes after parking
- Walking away from parked car: Should immediately release lock
- Highway driving: Should still detect quickly (10-15 seconds)

**Future Improvements (Phase 2 - Not Yet Implemented)**:
- Disable outdoor streak bonus when recent vehicle sample exists (reduces initial vehicle detection delay)
- Multi-sample confirmation for borderline vehicle confidence (reduces false positives from cyclists/joggers)
- Spatial context for parking detection using OSM parking lot polygons (distinguishes parking from red lights)

**Modified Files**:
- `sunwize/Services/Location/LocationManager.swift`: Fix #1 (threshold), Fix #3 (persistence)
- `sunwize/Services/Background/BackgroundTaskManager.swift`: Fix #2 (vehicle lock + parking detection)
- `CLAUDE.md`: Documentation updates (this file)