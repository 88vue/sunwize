# Sunwize - UI Functionality Brief

**Document Purpose:** This brief describes every user-facing feature and interaction in the Sunwize skin health app. It focuses on what users see and do, not technical implementation. Use this to design and build a complete, polished user interface.

---

## App Concept

Sunwize is a skin cancer prevention assistant that runs in the background, protecting users from UV overexposure. Users rarely need to interact with the app—it monitors their sun exposure automatically and sends smart notifications when they're at risk. The app balances sun safety with Vitamin D optimization and includes body spot tracking for early skin cancer detection.

**User Flow:** Set it up once → Let it run → Receive helpful notifications → Occasionally open to log sunscreen, check forecasts, or document skin spots.

---

## Navigation Structure

**Tab-Based Architecture:**
- **Tab 1:** UV + Vitamin D Tracking (default landing page)
- **Tab 2:** Body Spot
- **Tab 3:** Profile

**Bottom tab bar:** Always visible with icons for each section. Active tab highlighted in orange.

---

## Onboarding Flow

**Purpose:** First-time user education and profile setup. Must feel welcoming, informative, and fast (5-7 screens).

### Screen 1: Welcome
**What users see:**
- Animated sun icon (pulsing or glowing)
- App name "Sunwize"
- Tagline: "Your personal guide to skin cancer prevention"
- Brief feature list:
  - Track UV exposure automatically
  - Optimize Vitamin D safely
  - Monitor skin changes over time
- Large "Get Started" button

**Interactions:**
- Tap button → advance to next screen

---

### Screen 2: The Problem
**What users see:**
- Warning icon or illustration
- Bold headline: "Skin Cancer is Preventable"
- Key statistics in cards:
  - "2 in 3 Australians will be diagnosed"
  - "$1.8B annual healthcare cost"
  - "100% preventable with proper sun safety"
- "Learn How Sunwize Helps" button

**Interactions:**
- Tap button → advance to next screen
- Back button → return to welcome

---

### Screen 3: The Solution
**What users see:**
- Checkmark or shield icon
- Headline: "How Sunwize Protects You"
- Feature cards with icons:
  - Real-time UV tracking with smart alerts
  - Balanced Vitamin D monitoring
  - Early detection with body spots
- "Continue" button

**Interactions:**
- Tap button → advance to sign-in
- Back button → return to problem screen

---

### Screen 4: Authentication
**What users see:**
- App logo at top
- Headline: "Create Your Account" or "Sign In"
- Authentication options:
  - "Continue with Google" button (Google logo)
  - "Continue with Apple" button (Apple logo)
  - Email/password form (expandable)
- Already have account? / Need an account? toggle

**Email/Password Form (when expanded):**
- Email text field (email keyboard, validation)
- Password text field (secure entry, show/hide toggle)
- "Forgot password?" link
- "Sign In" or "Create Account" button

**Interactions:**
- Tap OAuth buttons → system authentication flow
- Enter email/password → validation → sign in/up
- Forgot password → password reset email flow
- On success → advance to profile setup

---

### Screen 5: Profile Setup
**What users see:**
- Progress indicator (5 of 7 dots filled)
- Icon or avatar placeholder
- Headline: "Tell Us About Yourself"
- Form fields:
  - **Name** (text input, required)
  - **Age** (number picker or text, 0-120, required)
  - **Gender** (dropdown/picker, required)
    - Options: Male, Female, Non-binary, Prefer not to say
  - **Skin Type** (interactive carousel, required)
    - 6 cards showing Fitzpatrick Scale I-VI
    - Each card: skin tone visual + type number + description
    - Swipe or tap arrows to browse
- "Continue" button (enabled when all fields valid)

**Interactions:**
- Fill all fields → enable continue button
- Tap continue → advance to personalized setup
- Back button → return to auth

**Validation:**
- Name: Cannot be empty
- Age: Must be 0-120
- All fields required before continuing

---

### Screen 6: Personalized Setup
**What users see:**
- Greeting: "Nice to meet you, [Name]!"
- Message: "We're calculating your personalized sun safety limits"
- Loading animation or progress indicator
- Info cards showing calculated values:
  - Your MED: [X] J/m²
  - Skin Type: Type [X] description
  - Daily Vitamin D Target: [X] IU (editable)
- Explanation text: "Based on your profile, we've personalized your UV thresholds"
- "Continue" button

**Interactions:**
- Review calculated values
- Optionally adjust Vitamin D target (tap to edit)
- Tap continue → advance to permissions

---

### Screen 7: Permissions
**What users see:**
- Icon for each permission
- Headline: "Final Step: Grant Permissions"
- Permission cards (3-4 cards):
  
  **Location Permission:**
  - Icon: Location pin
  - Title: "Location (Always)"
  - Description: "Tracks indoor/outdoor status in background"
  - Status indicator: Not granted / Granted (green checkmark)
  - "Enable" button
  
  **Camera Permission:**
  - Icon: Camera
  - Title: "Camera"
  - Description: "Take photos for body spot tracking"
  - Status indicator
  - "Enable" button
  
  **Notifications Permission:**
  - Icon: Bell
  - Title: "Notifications"
  - Description: "Receive UV warnings and reminders"
  - Status indicator
  - "Enable" button

- "Complete Setup" button (prominent, always enabled)
- "I'll do this later" skip link

**Interactions:**
- Tap "Enable" on each card → system permission prompt
- Permission granted → card shows green checkmark
- Permission denied → show "Open Settings" button on that card
- Tap "Complete Setup" → navigate to main app (UV Tracking tab)
- Permissions can be skipped but app functionality limited

---

## Tab 1: UV + Vitamin D Tracking

**Layout:** Two-page swipeable view with page indicator dots at top.

**Page Indicator:**
- Two dots (left = UV Exposure, right = Vitamin D)
- Active page: orange dot
- Inactive page: gray dot
- Positioned at top center of screen

---

### Page 1: UV Exposure Tracking

**Purpose:** Show real-time UV exposure status with context-aware displays.

#### State 1: Outside (Active UV Tracking)

**What users see:**

**Top Section:**
- UV Safe Streak badge (top right corner)
  - Shows: "[X] days" with shield icon
  - Tappable
  
**Main Display:**
- Large UV Index number (center, extra bold)
  - Color coded: Green (0-2), Yellow (3-5), Orange (6-7), Dark Orange (8-10), Red (11+)
  - Tappable to view forecast
- UV level description below number ("Low", "Moderate", "High", etc.)
- Arrow icon indicating tappable

**Exposure Indicator:**
- Battery-style progress bar (if sunscreen not active)
  - Gradient colors from green → yellow → red based on exposure ratio
  - Shows current session SED/MED percentage
  - Visual: horizontal battery with filling level
  
**Session Info:**
- Clock icon with session start time
- Small text: "Started at [time]"

**Sunscreen Section (if not applied):**
- Prominent blue button: "Apply Sunscreen"
- Hand icon on button
- Full width, rounded corners

**Sunscreen Section (if active):**
- Timer display showing remaining protection time
  - Large countdown: "1h 45m remaining"
  - Subtitle: "Sunscreen applied at [time]"
- Blue button: "Reapply Sunscreen"
- Protection status badge or indicator

**Recommendations (if approaching limits):**
- Warning card appears when 75%+ exposed
  - Orange background: "You're approaching your UV limit. Consider applying sunscreen or going inside."
- Danger card appears when 100%+ exposed
  - Red background: "⚠️ You've exceeded your safe UV limit! Seek shade immediately."

**Interactions:**
- Tap UV Index → opens UV Forecast modal
- Tap streak badge → opens UV History modal
- Tap "Apply Sunscreen" → starts 2-hour protection countdown, hides battery indicator
- Tap "Reapply Sunscreen" → resets 2-hour countdown
- Swipe left → go to Vitamin D page

---

#### State 2: Inside or In Vehicle

**What users see:**
- House icon (if inside) or car icon (if in vehicle)
- Message: "Looks like you're inside" or "Looks like you're in a vehicle"
- Current outdoor UV index (informational only)
  - "Current UV Index: [X.X]"
  
**Forecast Preview:**
- Card showing "Next 24 Hours"
- Embedded line chart of UV index over time
  - X-axis: Time (4-hour intervals)
  - Y-axis: UV index
  - Orange line
- Arrow icon in corner to expand to full forecast

**Interactions:**
- Tap arrow on forecast card → opens full UV Forecast modal
- Chart is non-interactive preview
- Swipe left → go to Vitamin D page

---

#### State 3: Night Time

**What users see:**
- Moon and stars icon
- Message: "Looks like it's night time"
- Subtitle: "No UV exposure at night"

**Tomorrow's Forecast:**
- Card labeled "Tomorrow's Forecast"
- Embedded line chart of tomorrow's UV forecast
  - Same chart style as inside view
- Arrow to expand

**Interactions:**
- Tap arrow → opens full UV Forecast modal
- Swipe left → go to Vitamin D page

---

#### State 4: Location Unknown

**What users see:**
- Question mark icon in orange
- Headline based on reason:
  - "We're still learning this area" (no building data)
  - "Location signal is weak" (poor GPS)
  - "Need more evidence" (insufficient data)
  - "Detecting your location" (default)
  
- Description explaining the issue
- Confidence indicator: "Detection confidence [X]%"

**Action Buttons:**
- "Retry Detection" button (orange background)
  - Circular arrow icon
- "View UV Forecast" button (orange outline)
  - Chart icon
- "Check Location Settings" button (orange outline, only for GPS issues)
  - Location pin icon
  - Opens system settings

**Interactions:**
- Tap Retry → force refresh location detection
- Tap Forecast → opens UV Forecast modal
- Tap Settings → opens iOS Settings app
- Swipe left → go to Vitamin D page

---

#### State 5: UV Tracking Disabled

**What users see:**
- Gray exclamation icon
- Message: "UV Tracking is disabled"
- "Enable in Settings" link (orange text, acts as button)

**Interactions:**
- Tap link → navigates to Profile tab
- Forecast still accessible if user navigates elsewhere
- Swipe left → go to Vitamin D page

---

### Page 2: Vitamin D Tracking

**What users see:**

**Top Section:**
- Daily target badge (top left)
  - Shows: "[Current] / [Target] IU"
  - Tappable to edit target
- Vitamin D Streak badge (top right)
  - Shows: "[X] days" with sparkles icon
  - Tappable

**Main Display (when enabled):**
- Battery-style progress indicator (no gradient, solid yellow fill)
  - Shows progress toward daily IU target
  - Percentage visible

**IU Display:**
- Large number: "[X] IU" (current amount synthesized today)
- Subtitle: "of [Target] IU daily target"

**Body Exposure Control:**
- Titled "Body Exposure"
- Icon showing current clothing level
- Label describing current setting:
  - "Face & Hands" (10% exposed)
  - "T-shirt & Shorts" (30%)
  - "Tank Top & Shorts" (50%)
  - "Swimwear" (80%)
- Percentage indicator: "[X]% skin exposed"

**Slider:**
- Horizontal slider from swimwear (left) to fully clothed (right)
- Icons at both ends
- Snaps to 4 preset levels
- Labeled tick marks below slider

**Info Text:**
- Small caption: "Adjust based on your clothing to get accurate Vitamin D calculations"

**Disabled State:**
- Gray icon
- Message: "Vitamin D Tracking is disabled"
- "Enable in Settings" link

**Interactions:**
- Tap target badge → opens Target Editor modal
- Tap streak badge → opens Vitamin D History modal
- Drag slider → immediate update, visual feedback, saves automatically
- Tap preset levels on slider → jumps to that level
- Swipe right → go back to UV Exposure page

---

### Modal: UV Forecast

**What users see:**
- Navigation header: "UV Forecast" with "Done" button
- Page indicator (if multiple days): "1 / 5"
- Small dots showing current day page

**Per Page (24-hour period):**
- Page title: "Today's Forecast", "Tomorrow's Forecast", or date
- Large interactive chart:
  - Line chart with gradient fill underneath
  - X-axis: Time (3-hour intervals with am/pm)
  - Y-axis: UV index (0-15)
  - Orange line and gradient
  - Pinch to zoom, pan to scroll time
  
**Peak UV Section:**
- "Peak UV Time" heading
- Card showing:
  - Sun icon
  - Time of peak: "[time]"
  - UV index at peak: "UV Index: [X.X]"
  - Orange background tint

**UV Index Guide:**
- Table/list showing all risk levels:
  - Colored dot for each level
  - UV range ("0-2", "3-5", etc.)
  - Description ("Low", "Moderate", etc.)
  
**Interactions:**
- Swipe left/right → switch between day pages
- Pinch chart → zoom in/out
- Tap "Done" → close modal

---

### Modal: UV History

**What users see:**
- Navigation header: "UV Safe History" with "Done" button
- 7-day calendar/list view
- Each day shows:
  - Date
  - Green checkmark (if stayed under MED)
  - Red warning icon (if exceeded MED)
  - Gray icon (if future date or no data)
  - UV exposure amount: "[X.X] SED"
  - MED percentage: "[X]% of your MED"

**Interactions:**
- Scroll to see more days
- Tap day → potentially show detail (optional)
- Tap "Done" → close modal

---

### Modal: Vitamin D History

**What users see:**
- Navigation header: "Vitamin D History" with "Done" button
- Bar chart showing:
  - Last 7 days
  - Vertical bars for each day's IU total
  - Horizontal line showing daily target
  - Bars that exceed target highlighted differently
  - Y-axis: IU amount
  - X-axis: Day abbreviations (M, T, W, etc.)

**Data Cards:**
- "This Week: [Total] IU"
- "Average: [Avg] IU/day"
- "Target Achievement: [X]/7 days"

**Interactions:**
- Tap bar → show exact value for that day (optional)
- Tap "Done" → close modal

---

### Modal: Vitamin D Target Editor

**What users see:**
- Navigation header: "Daily Target" with "Cancel" and "Save" buttons
- Current target display: "[Current] IU"
- Large text input field
  - Number keyboard
  - Placeholder: "Enter target (1-20,000 IU)"
- Info text: "Recommended: 600-4,000 IU per day"
- Preset buttons:
  - "600 IU" (minimum)
  - "1,000 IU" (standard)
  - "2,000 IU" (optimal)
  - "4,000 IU" (maximum safe)

**Interactions:**
- Tap text field → enter custom value
- Tap preset button → sets that value
- Tap "Save" → saves and closes modal
- Tap "Cancel" → discards changes and closes

---

## Tab 2: Body Spot

**Purpose:** Visual skin tracking using 3D body model to log and monitor spots over time.

### Main View: 3D Model Screen

**What users see:**

**Header (when visible):**
- Title: "Body Spot Tracker"
- Spot count: "[X] spots tracked"
- Body icon (orange)

**3D Model Section:**
- Full-screen interactive 3D human figure (neutral, anatomically accurate)
- Orange dot markers on body showing logged spots
  - Marker size indicates number of logs at that location
- Loading state: Spinner with "Loading 3D Model..." text
  - Loading overlay covers model until ready

**Instructions Banner:**
- Semi-transparent black bar at bottom
- White text: "Double tap to add a new spot or zoom and tap orange dots to view existing spots"
- Rounded corners
- Positioned over bottom of 3D view

**Interactions:**
- **Rotate:** Single-finger drag to rotate model around vertical axis
- **Zoom:** Pinch to zoom in/out
- **Pan:** Two-finger drag to move model up/down/left/right
- **Double tap on body:** Opens "Add New Spot" form at that location
- **Single tap on orange marker:** Opens Spot Timeline for that location
- Smooth animations for all gestures

---

### Bottom Sheet: Spot Timeline

**Triggered by:** Tapping existing orange marker on 3D model

**What users see:**
- Sheet slides up from bottom, covers lower 30-40% of screen
- 3D model shrinks to top 60% (still visible and interactive)
- Rounded top corners with drag handle

**Content:**
- **Header:**
  - Body part label: "Left Forearm", "Upper Back", etc.
  - "[X] logs" count
  - "Add New Log" button (orange)
  - Close button (X)

**Timeline Display:**
- Horizontal scrollable row of spot photos
- Each entry shows:
  - Thumbnail photo (square, rounded corners)
  - Date below photo
- Entries sorted chronologically (newest first)
- Tappable entries

**Interactions:**
- Swipe down on sheet → close timeline, return to full model
- Tap close button → same as swipe down
- Scroll horizontally → see more log entries
- Tap photo → opens Spot Detail modal (full screen)
- Tap "Add New Log" → opens Spot Form for this location

---

### Full Screen: Spot Form

**Triggered by:** Double-tapping model or tapping "Add New Log"

**What users see:**
- Form takes entire screen, 3D model hidden
- Header with Cancel (left), title (center), Save (right)
  - Title: "New Spot" or "Add Log"
  - Save button disabled until photo taken

**Scrollable Form:**

**Photo Section:**
- Large square preview area
- If no photo:
  - Camera icon (large, gray)
  - "Take Photo" button (blue)
  - "Choose from Library" button (outline)
- If photo taken:
  - Full photo preview
  - X button to remove (top right corner of photo)
  - Camera overlays/guides optional

**Body Part (auto-filled):**
- Read-only field or label
- Shows detected body part from 3D coordinates
- Icon for body part

**ABCDE Assessment Section:**
Each criterion as separate field:

**Asymmetry:**
- Label: "Asymmetry"
- Toggle switch: Yes / No
- Info icon (? in circle) with explanation

**Border:**
- Label: "Border"
- Dropdown/picker with options:
  - Regular
  - Irregular
  - Ragged

**Color:**
- Label: "Color"
- Dropdown/picker with options:
  - Uniform
  - Varied
  - Multicolor

**Diameter:**
- Label: "Diameter (mm)"
- Slider: 0-10mm with tick marks
- Current value displayed above slider

**Evolving:**
- Label: "Changes Over Time"
- Segmented control or radio buttons:
  - Shrunk
  - Unchanged
  - Grown

**Additional Fields:**

**Description (optional):**
- Label: "Description"
- Multi-line text input
- Placeholder: "What does this spot look like?"

**Notes (optional):**
- Label: "Notes"
- Multi-line text input
- Placeholder: "Any concerns or observations?"

**Validation:**
- Photo is required
- At least one ABCDE field should be filled
- Save button only enabled when valid

**Interactions:**
- Tap "Take Photo" → opens camera view with overlay
- Tap "Choose from Library" → opens iOS photo picker
- Fill out form fields → auto-save as draft
- Tap "Save" → uploads photo, saves data, returns to timeline view
- Tap "Cancel" → confirmation alert if photo taken, then discards and returns

---

### Modal: Spot Detail View

**Triggered by:** Tapping photo in timeline

**What users see:**
- Full-screen modal
- Navigation header: "Spot Details" with "Done" and share icon
- Close button

**Photo Section:**
- Large photo (full width, landscape aspect)
- Share and download icons on photo

**Details Section (scrollable):**

**Date Card:**
- Calendar icon
- "Logged on [full date]"

**ABCDE Assessment Card:**
- Each criterion shown as row:
  - Icon for criterion
  - Label
  - Value/answer
- Color coding for concerning values (optional)

**Description Card (if filled):**
- Quote icon
- Full description text

**Notes Card (if filled):**
- Note icon
- Full notes text

**Body Part Card:**
- Body icon
- "[Body part] - Left/Right"

**Actions:**
- "Delete Log" button (red, outline, bottom)
  - Requires confirmation alert

**Interactions:**
- Tap share icon → iOS share sheet (photo + optional PDF)
- Tap download → saves photo to device photos
- Swipe to dismiss or tap "Done" → return to timeline
- Tap "Delete" → confirmation alert → deletes and returns to timeline

---

### Camera View (when taking photo)

**What users see:**
- Full-screen camera preview
- Flash toggle (top left)
- Camera flip toggle (top right, if front camera available)
- Circular shutter button (center bottom)
- Cancel button (top left or bottom left)

**Optional overlay guides:**
- Circle outline for spot framing
- Grid for alignment
- Brightness/contrast indicators

**Interactions:**
- Tap shutter → captures photo, returns to form with photo
- Tap cancel → returns to form without photo
- Pinch to zoom camera
- Tap on preview to focus

---

## Tab 3: Profile

**Purpose:** User account info, skin profile, app settings, and achievements.

### Main Profile Screen

**What users see (scrollable):**

**Header Section:**
- Gradient background (orange to yellow)
- Large circular avatar
  - Gradient fill (orange/yellow)
  - User initials in white (first 2 letters of name)
- User's full name (bold, large)
- Email address (smaller, gray)
- "Member since [Month Year]" (small, gray)

**Stats Cards Section:**
- Two side-by-side cards of equal size
- Left card: UV Safe Streak
  - Shield icon (green)
  - Large number: "[X] days"
  - Label: "UV Safe Streak"
- Right card: Vitamin D Streak
  - Sparkles icon (yellow)
  - Large number: "[X] days"
  - Label: "Vitamin D Streak"
- Cards have subtle shadow, white background

**Skin Profile Section:**
- Section header: "Skin Profile" with sun icon
- White card containing:
  - **Skin Type:** Type number with full Fitzpatrick description
    - "Type II - Burns easily, tans minimally"
  - **Age:** "[X] years"
  - **MED Value:** "[X] J/m²" with explanation
    - Subtitle: "Personalized minimal erythemal dose"
- Each item is a row with label and value
- Dividers between rows (optional)

**Feature Settings Section:**
- Section header: "Feature Settings" with gear icon
- White card containing toggle rows:
  
  **UV Tracking Toggle:**
  - Sun icon (orange)
  - Title: "UV Tracking"
  - Description: "Monitor UV exposure when outside"
  - Toggle switch (orange when on)
  
  **Vitamin D Tracking Toggle:**
  - Sparkles icon (yellow)
  - Title: "Vitamin D Tracking"
  - Description: "Calculate Vitamin D synthesis"
  - Toggle switch (orange when on)
  
  **Body Spot Reminders Toggle:**
  - Bell icon (orange)
  - Title: "Body Spot Reminders"
  - Description: "Monthly reminders for body spots"
  - Toggle switch (orange when on)
  
- Dividers between toggle rows

**Action Buttons:**
- "Edit Profile" button
  - Orange background (tinted, not solid)
  - Orange text
  - Person/document icon
  - Full width, rounded corners
  - Medium padding
  
- "Sign Out" button
  - White background
  - Red text and red border
  - Sign-out icon
  - Full width, rounded corners

**Footer:**
- App version: "Sunwize v1.0.0" (small, centered, gray)
- Tagline: "Made with ☀️ for your skin health" (small, centered, gray)
- Extra padding at bottom

**Interactions:**
- Tap stats cards → potentially show detailed history (optional, may not be implemented)
- Toggle switches → instant visual feedback, persists to database
  - Shows loading spinner briefly
  - Can't toggle off if critical
- Tap "Edit Profile" → opens Edit Profile modal
- Tap "Sign Out" → confirmation alert → signs out and returns to authentication

---

### Modal: Edit Profile

**Triggered by:** Tapping "Edit Profile" button

**What users see:**
- Sheet modal (covers ~80% of screen)
- Navigation header: "Edit Profile" with "Cancel" and "Save" buttons
- Save button disabled until changes made

**Form Fields (scrollable):**
- **Name:**
  - Text input
  - Current value pre-filled
  - Validation: Cannot be empty
  
- **Age:**
  - Number input or picker
  - Current value pre-filled
  - Range: 0-120
  
- **Gender:**
  - Picker/dropdown
  - Options: Male, Female, Non-binary, Prefer not to say
  - Current value selected
  
- **Skin Type:**
  - Same carousel as onboarding
  - Shows all 6 Fitzpatrick types
  - Current type pre-selected
  - Swipeable or arrows to navigate
  
- **Email (read-only):**
  - Grayed out, cannot edit
  - Shows current email
  - Info: "Contact support to change email"

**MED Recalculation Notice (if skin type, age, or gender changed):**
- Info box with yellow/orange background
- Icon: Exclamation in circle
- Message: "Changing these values will recalculate your MED"
- New MED value preview

**Interactions:**
- Edit any field → enables "Save" button
- Tap "Save" → validates, saves to database, closes modal, updates profile display
- Tap "Cancel" → discards changes, closes modal
- Shows loading spinner during save
- Error message if save fails

---

### Alert: Sign Out Confirmation

**Triggered by:** Tapping "Sign Out" button

**What users see:**
- iOS-style alert dialog
- Title: "Sign Out"
- Message: "Are you sure you want to sign out?"
- Two buttons:
  - "Sign Out" (red, destructive style)
  - "Cancel" (default style)

**Interactions:**
- Tap "Sign Out" → signs user out, navigates to authentication screen
- Tap "Cancel" → dismisses alert, stays on profile

---

## Shared UI Components

### Battery Indicator
**Purpose:** Visual progress bar for UV exposure and Vitamin D

**What users see:**
- Horizontal battery shape
- Fill level based on progress percentage
- UV Exposure variant: Gradient from green → yellow → orange → red
- Vitamin D variant: Solid yellow fill, no gradient
- Percentage text overlaid or adjacent
- Clean, modern style

### Streak Badge
**Purpose:** Show achievement streaks

**What users see:**
- Compact badge/pill shape
- Icon (shield for UV, sparkles for Vitamin D)
- Number with "days" label
- Background tint matching icon color
- Tappable affordance (subtle shadow or border)

### Target Badge
**Purpose:** Show Vitamin D progress toward goal

**What users see:**
- Badge showing: "[Current] / [Target] IU"
- Edit icon or indicator that it's tappable
- Orange/yellow color scheme

### Recommendation Cards
**Purpose:** Alert users to take action

**Variants:**
- Warning (orange background): Used at 75% exposure
- Danger (red background): Used at 100% exposure
- Info (blue background): General tips

**What users see:**
- Full-width card
- Icon (warning triangle, info circle, etc.)
- Bold message text
- White text on colored background
- Rounded corners, shadow

### Page Indicator Dots
**Purpose:** Show current page in swipeable views

**What users see:**
- Row of small circles
- Active page: orange filled circle
- Inactive pages: gray outline circles
- Centered at top of swipeable area

---

## Visual Design Principles

*Note: These are descriptions of the current app, not prescriptive requirements. The AI designer should create their own design that fulfills these functional requirements.*

**Current characteristics users expect:**
- Orange as primary brand color (sun/warmth theme)
- Clean, modern iOS-style interface
- Card-based layout for grouped information
- Generous white space and padding
- Clear visual hierarchy with bold headings
- Color-coded risk levels (green = safe, yellow = moderate, red = danger)
- Smooth animations and transitions
- System fonts with various weights for emphasis
- Icons from SF Symbols (iOS) or Material Icons (Android)

---

## Accessibility Requirements

**Must support:**
- Dynamic Type (text size adjustments)
- VoiceOver / TalkBack screen readers
- High contrast mode
- Sufficient touch target sizes (44pt minimum)
- Color is not the only indicator (icons + text for all states)
- Keyboard navigation where applicable
- Clear focus indicators

**Labels needed for screen readers:**
- All interactive elements
- All informational icons
- Chart data points
- Toggle switch states
- Form field purposes

---

## Error States & Edge Cases

### No Internet Connection
- Show message: "No connection. Using last known data."
- Allow offline viewing of cached data
- Disable features requiring network (forecast, sync)
- Show retry button when applicable

### Location Permission Denied
- Show in UV Tracking: "Location permission required"
- Provide "Open Settings" button
- Explain why permission is needed
- Show UV forecast as fallback

### No Spots Logged Yet (Body Spot)
- Show empty state illustration
- Message: "No spots tracked yet"
- Instructions: "Double tap the body model to add your first spot"
- Welcoming tone, not discouraging

### Failed Photo Upload
- Show error message: "Failed to upload photo"
- "Retry" button
- "Save as draft" option
- Don't lose form data

### API Failures
- UV data unavailable: Show last cached value with timestamp
- Forecast unavailable: Show message, hide chart
- Graceful degradation, never hard crash

---

## Notifications

*Note: These trigger automatically in background; users just see the notifications.*

**Types users receive:**

### UV Warning (75% of MED)
- Title: "UV Alert"
- Body: "You're at 75% of your safe UV limit. Consider applying sunscreen or finding shade."
- Icon: Sun with warning triangle
- Tapping: Opens app to UV Tracking tab

### UV Danger (100% of MED)
- Title: "⚠️ UV Danger"
- Body: "You've exceeded your safe UV limit! Seek shade immediately."
- Icon: Sun with X
- Sound: More urgent alert sound
- Tapping: Opens app to UV Tracking tab

### Vitamin D Target Achieved
- Title: "🎉 Daily Goal Reached!"
- Body: "You've synthesized your target Vitamin D for today."
- Icon: Sparkles
- Tapping: Opens app to Vitamin D page

### Body Spot Reminder (Monthly)
- Title: "Monthly Body Check"
- Body: "Time for your monthly body spot. Check for any new or changing spots."
- Icon: Camera
- Tapping: Opens app to Body Spot tab

### Sunscreen Expiring Soon
- Title: "Sunscreen Check"
- Body: "Your sunscreen protection expires in 15 minutes. Reapply soon."
- Icon: Hand with cream
- Tapping: Opens app to UV Tracking tab

---

## Conclusion

This document describes every screen, component, interaction, and edge case in the Sunwize app from a user interface perspective. The goal is to help a designer or AI system understand exactly what users see and do at every step. Implementation details and technical architecture are intentionally excluded—focus on creating an intuitive, delightful experience that keeps users safe from skin cancer.
