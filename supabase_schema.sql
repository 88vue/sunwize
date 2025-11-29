-- Sunwize App - Supabase Database Schema
-- Run this in your Supabase SQL Editor to create all required tables

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- PROFILES TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    age INTEGER NOT NULL CHECK (age > 0 AND age <= 120),
    gender TEXT NOT NULL,
    skin_type INTEGER NOT NULL CHECK (skin_type BETWEEN 1 AND 6),
    med INTEGER NOT NULL CHECK (med > 0),
    onboarding_completed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Policies for profiles
CREATE POLICY "Users can view own profile"
    ON profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON profiles FOR UPDATE
    USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile"
    ON profiles FOR INSERT
    WITH CHECK (auth.uid() = id);

-- ============================================
-- UV SESSIONS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS uv_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    session_sed DOUBLE PRECISION DEFAULT 0,
    sunscreen_applied BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT valid_end_time CHECK (end_time IS NULL OR end_time >= start_time)
);

-- Indexes
CREATE INDEX idx_uv_sessions_user_date ON uv_sessions(user_id, date);
CREATE INDEX idx_uv_sessions_created ON uv_sessions(created_at);

-- Enable Row Level Security
ALTER TABLE uv_sessions ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view own sessions"
    ON uv_sessions FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own sessions"
    ON uv_sessions FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own sessions"
    ON uv_sessions FOR UPDATE
    USING (auth.uid() = user_id);

-- ============================================
-- VITAMIN D DATA TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS vitamin_d_data (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    total_iu DOUBLE PRECISION DEFAULT 0 CHECK (total_iu >= 0),
    target_iu DOUBLE PRECISION DEFAULT 600 CHECK (target_iu > 0),
    body_exposure_factor DOUBLE PRECISION DEFAULT 0.3 CHECK (body_exposure_factor BETWEEN 0 AND 1),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, date)
);

-- Indexes
CREATE INDEX idx_vitamin_d_user_date ON vitamin_d_data(user_id, date);

-- Enable Row Level Security
ALTER TABLE vitamin_d_data ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view own vitamin D data"
    ON vitamin_d_data FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own vitamin D data"
    ON vitamin_d_data FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own vitamin D data"
    ON vitamin_d_data FOR UPDATE
    USING (auth.uid() = user_id);

-- ============================================
-- BODY LOCATION TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS body_location (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    coord_x DOUBLE PRECISION NOT NULL,
    coord_y DOUBLE PRECISION NOT NULL,
    coord_z DOUBLE PRECISION NOT NULL,
    body_part TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_body_location_user ON body_location(user_id);

-- Enable Row Level Security
ALTER TABLE body_location ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view own body locations"
    ON body_location FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own body locations"
    ON body_location FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- ============================================
-- BODY SPOTS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS body_spots (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    location_id UUID NOT NULL REFERENCES body_location(id) ON DELETE CASCADE,
    image_url TEXT,
    description TEXT,
    body_part TEXT NOT NULL,
    asymmetry BOOLEAN DEFAULT FALSE,
    border TEXT,
    color TEXT,
    diameter DOUBLE PRECISION,
    evolving TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_body_spots_location ON body_spots(location_id);
CREATE INDEX idx_body_spots_created ON body_spots(created_at DESC);

-- Enable Row Level Security
ALTER TABLE body_spots ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view own body spots"
    ON body_spots FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM body_location bl
            WHERE bl.id = body_spots.location_id
            AND bl.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can insert own body spots"
    ON body_spots FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM body_location bl
            WHERE bl.id = location_id
            AND bl.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can update own body spots"
    ON body_spots FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM body_location bl
            WHERE bl.id = body_spots.location_id
            AND bl.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can delete own body spots"
    ON body_spots FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM body_location bl
            WHERE bl.id = body_spots.location_id
            AND bl.user_id = auth.uid()
        )
    );

-- ============================================
-- STREAKS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS streaks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
    uv_safe_streak INTEGER DEFAULT 0 CHECK (uv_safe_streak >= 0),
    vitamin_d_streak INTEGER DEFAULT 0 CHECK (vitamin_d_streak >= 0),
    last_updated TIMESTAMPTZ DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE streaks ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view own streaks"
    ON streaks FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own streaks"
    ON streaks FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own streaks"
    ON streaks FOR UPDATE
    USING (auth.uid() = user_id);

-- ============================================
-- FEATURE SETTINGS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS feature_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
    uv_tracking_enabled BOOLEAN DEFAULT TRUE,
    vitamin_d_tracking_enabled BOOLEAN DEFAULT TRUE,
    body_scan_reminders_enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE feature_settings ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view own feature settings"
    ON feature_settings FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own feature settings"
    ON feature_settings FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own feature settings"
    ON feature_settings FOR UPDATE
    USING (auth.uid() = user_id);

-- ============================================
-- FUNCTIONS AND TRIGGERS
-- ============================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
CREATE TRIGGER update_profiles_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_vitamin_d_data_updated_at
    BEFORE UPDATE ON vitamin_d_data
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_body_spots_updated_at
    BEFORE UPDATE ON body_spots
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_feature_settings_updated_at
    BEFORE UPDATE ON feature_settings
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Function to create default settings on profile creation
CREATE OR REPLACE FUNCTION create_default_user_data()
RETURNS TRIGGER AS $$
BEGIN
    -- Create default streaks
    INSERT INTO streaks (user_id, uv_safe_streak, vitamin_d_streak)
    VALUES (NEW.id, 0, 0);
    
    -- Create default feature settings
    INSERT INTO feature_settings (user_id)
    VALUES (NEW.id);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to create default data when profile is created
CREATE TRIGGER on_profile_created
    AFTER INSERT ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION create_default_user_data();

-- ============================================
-- STORAGE BUCKET FOR BODY SCAN IMAGES
-- ============================================
-- Run this in Supabase Storage section or via SQL:
-- 
-- INSERT INTO storage.buckets (id, name, public)
-- VALUES ('body-spots', 'body-spots', false);
--
-- Create policy for storage bucket:
-- CREATE POLICY "Users can upload own body spot images"
--     ON storage.objects FOR INSERT
--     WITH CHECK (bucket_id = 'body-spots' AND auth.uid()::text = (storage.foldername(name))[1]);
--
-- CREATE POLICY "Users can view own body spot images"
--     ON storage.objects FOR SELECT
--     USING (bucket_id = 'body-spots' AND auth.uid()::text = (storage.foldername(name))[1]);
