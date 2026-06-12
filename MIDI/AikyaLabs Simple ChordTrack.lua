-- @description AikyaLabs Simple ChordTrack
-- @author Aikya Labs
-- @version 1.2.0
-- @provides
--   [main] AikyaLabs Simple ChordTrack.lua
--   logo_processed.png
-- @about
--   A highly integrated, Studio One inspired native Chord Track and real-time Display system for REAPER.
--   Features a modern flat-design UI using ReaImGui.

local r = reaper

local imgui_path = r.ImGui_GetBuiltinPath and r.ImGui_GetBuiltinPath()
if not imgui_path then
    r.ShowMessageBox("Please install ReaImGui from ReaPack to use this script.", "Error", 0)
    return
end

package.path = imgui_path .. '/?.lua'
local ImGui = require 'imgui' '0.9'

local ctx = ImGui.CreateContext('Chord Track Editor', ImGui.ConfigFlags_None)

local font_main = ImGui.CreateFont('sans-serif', 15)
local font_h1   = ImGui.CreateFont('sans-serif', 80)
local font_h2   = ImGui.CreateFont('sans-serif', 24)
local font_sm   = ImGui.CreateFont('sans-serif', 12)

ImGui.Attach(ctx, font_main)
ImGui.Attach(ctx, font_h1)
ImGui.Attach(ctx, font_h2)
ImGui.Attach(ctx, font_sm)

local script_path = debug.getinfo(1, 'S').source:match("@?(.*[\\/])") or ""
local logo_img = nil
if ImGui.CreateImage then
    logo_img = ImGui.CreateImage(script_path .. "logo_processed.png")
end

-- ==============================================================
-- DATA: Circle of Fifths root order
-- ==============================================================
local cof_roots = {"C","G","D","A","E","B","F#","Db","Ab","Eb","Bb","F"}
local cof_pc    = {  0,  7,  2,  9,  4, 11,   6,   1,   8,   3,  10,  5}

-- Mapping from chromatic index (1-12) to CoF index (for diatonic lookup)
-- cof_pc[i] gives pitch class of cof position i
local pc_to_cof = {}
for i, pc in ipairs(cof_pc) do pc_to_cof[pc] = i end

-- ==============================================================
-- DATA: Base Qualities (triads & suspended — no 7ths)
-- ==============================================================
local base_qualities = {
    {name="Major", short="",     intervals={0,4,7}},
    {name="Minor", short="m",    intervals={0,3,7}},
    {name="Dim",   short="dim",  intervals={0,3,6}},
    {name="Aug",   short="aug",  intervals={0,4,8}},
    {name="Sus2",  short="sus2", intervals={0,2,7}},
    {name="Sus4",  short="sus4", intervals={0,5,7}},
}

-- ==============================================================
-- DATA: Tensions (additive — stacked on top of base quality)
-- ==============================================================
-- Seventh type intervals (added to base quality)
-- 0=none, 1=dominant b7 (10), 2=maj7 (11), 3=dim7 (9)
local SEVENTH_INTERVALS = {10, 11, 9}
local SEVENTH_LABELS    = {"7", "maj7", "dim7"}

-- ==============================================================
-- DATA: Scales (diatonic pitch class sets, relative to root)
-- ==============================================================
local scales = {
    {name="Major",          intervals={0,2,4,5,7,9,11}},
    {name="Natural Minor",  intervals={0,2,3,5,7,8,10}},
    {name="Dorian",         intervals={0,2,3,5,7,9,10}},
    {name="Mixolydian",     intervals={0,2,4,5,7,9,10}},
    {name="Harmonic Minor", intervals={0,2,3,5,7,8,11}},
}

-- Diatonic base quality per scale degree (for key awareness highlighting)
-- Indexed [scale_idx][degree 0..6] -> base_quality index (1-6)
local diatonic_qualities = {
    -- Major: I=Maj, ii=Min, iii=Min, IV=Maj, V=Maj, vi=Min, vii=Dim
    [1] = {1,2,2,1,1,2,3},
    -- Natural Minor: i=Min, ii=Dim, III=Maj, iv=Min, v=Min, VI=Maj, VII=Maj
    [2] = {2,3,1,2,2,1,1},
    -- Dorian: i=Min, ii=Min, III=Maj, IV=Maj, v=Min, vi=Dim, VII=Maj
    [3] = {2,2,1,1,2,3,1},
    -- Mixolydian: I=Maj, ii=Min, iii=Dim, IV=Maj, v=Min, vi=Min, VII=Maj
    [4] = {1,2,3,1,2,2,1},
    -- Harmonic Minor: i=Min, ii=Dim, III=Aug, iv=Min, V=Maj, VI=Maj, vii=Dim
    [5] = {2,3,4,2,1,1,3},
}

-- ==============================================================
-- STATE
-- ==============================================================
local selected_cof_idx     = 1   -- which CoF segment (1-12)
local selected_quality_idx = 1   -- index into base_qualities
local selected_bass_idx    = 0   -- 0 = no bass note; 1-12 = cof_roots bass
local selected_octave      = 3
local selected_duration    = 1.0 -- bar multiplier: 0.5 / 1 / 2 / 4
local track_pinned         = false
-- Tension state (musically correct hierarchy)
local sel_seventh     = 0      -- 0=none 1=b7(dom) 2=maj7 3=dim7
local sel_nat_ext     = 0      -- 0=none 1=9th 2=11th 3=13th (each implies prior)
local sel_alt_b9      = false  -- alteration: flat 9
local sel_alt_s9      = false  -- alteration: sharp 9
local sel_alt_s11     = false  -- alteration: sharp 11
local sel_alt_b13     = false  -- alteration: flat 13

local key_root_pc   = -1  -- -1 = no key set; 0-11 = pitch class
local key_scale_idx = 1   -- index into scales

-- Persistent color
local user_color_hex = r.GetExtState("AikyaLabs_ChordTrack", "TrackColor")
local current_track_color = 0xB44C36FF
if user_color_hex ~= "" then
    current_track_color = tonumber(user_color_hex)
end

-- ==============================================================
-- BRAND COLORS
-- ==============================================================
local C_BG_DARK        = 0x1A1C1EFF
local C_BG_SURFACE     = 0x25282BFF
local C_TEXT_PRIMARY   = 0xF3EBE1FF
local C_TEXT_SECONDARY = 0xC4BDB5FF
local C_UI_TEAL        = 0x1A4B4FFF
local C_UI_TEAL_HOVER  = 0x215C61FF
local C_UI_TEAL_ACTIVE = 0x143A3DFF
local C_CTA_BRICK      = 0xB44C36FF
local C_CTA_HOVER      = 0xC55D47FF
local C_CTA_ACTIVE     = 0xA33B25FF
local C_BORDER_BROWN   = 0x7A4B3AFF
local C_GOLD           = 0xD4A838FF  -- diatonic highlight border

-- ==============================================================
-- KEY / DIATONIC HELPERS
-- ==============================================================
local function GetDiatonicPCs()
    if key_root_pc < 0 then return nil end
    local scale = scales[key_scale_idx]
    local pcs = {}
    for _, interval in ipairs(scale.intervals) do
        pcs[(key_root_pc + interval) % 12] = true
    end
    return pcs
end

-- Returns true if root pitch class is diatonic to current key
local function IsRootDiatonic(pc)
    local dpc = GetDiatonicPCs()
    if not dpc then return true end -- no key set => everything allowed
    return dpc[pc] == true
end

-- Returns true if the given base_quality is the "correct" diatonic quality
-- for the currently selected root in the current key/scale
local function IsQualityDiatonic(q_idx)
    if key_root_pc < 0 then return true end
    local scale = scales[key_scale_idx]
    -- Find the scale degree of selected root
    local root_pc = cof_pc[selected_cof_idx]
    local degree = nil
    for d, interval in ipairs(scale.intervals) do
        if (key_root_pc + interval) % 12 == root_pc then
            degree = d; break
        end
    end
    if not degree then return false end -- root not in key
    local dq = diatonic_qualities[key_scale_idx]
    if not dq then return true end
    return dq[degree] == q_idx
end

-- Returns true if a given compound semitone interval is diatonic
local function IsIntervalDiatonic(compound)
    if key_root_pc < 0 then return true end
    local dpc = GetDiatonicPCs()
    local root_pc = cof_pc[selected_cof_idx]
    return dpc[(root_pc + compound) % 12] == true
end

-- ==============================================================
-- UI HELPERS
-- ==============================================================
local function ToggleButton(label, selected, width, height, dim)
    height = height or 28
    dim = dim or false
    local clicked = false
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 1)
    
    if selected then
        ImGui.PushStyleColor(ctx, ImGui.Col_Border, C_UI_TEAL_HOVER)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, C_UI_TEAL)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C_UI_TEAL_HOVER)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C_UI_TEAL_ACTIVE)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, C_TEXT_PRIMARY)
    elseif dim then
        ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0x3A2A1AFF)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x1E2022FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x252829FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x1A1C1EFF)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x55514EFF)
    else
        ImGui.PushStyleColor(ctx, ImGui.Col_Border, C_BORDER_BROWN)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, C_BG_SURFACE)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x303438FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x1A1C1EFF)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, C_TEXT_SECONDARY)
    end

    if ImGui.Button(ctx, label, width, height) then clicked = true end

    ImGui.PopStyleColor(ctx, 5)
    ImGui.PopStyleVar(ctx, 1)
    return clicked
end

-- A toggle button with a gold diatonic border indicator
local function DiatonicToggleButton(label, selected, width, is_diatonic, key_set)
    local clicked = false
    local border_color = C_BORDER_BROWN
    local dim = false
    if key_set then
        if is_diatonic then
            border_color = C_GOLD
        else
            dim = true
        end
    end

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, is_diatonic and key_set and 2 or 1)

    if selected then
        ImGui.PushStyleColor(ctx, ImGui.Col_Border, C_UI_TEAL_HOVER)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, C_UI_TEAL)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C_UI_TEAL_HOVER)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C_UI_TEAL_ACTIVE)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, C_TEXT_PRIMARY)
    elseif dim then
        ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0x3A2A1AFF)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x1E2022FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x252829FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x1A1C1EFF)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x55514EFF)
    else
        ImGui.PushStyleColor(ctx, ImGui.Col_Border, border_color)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, C_BG_SURFACE)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x303438FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x1A1C1EFF)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, is_diatonic and key_set and C_TEXT_PRIMARY or C_TEXT_SECONDARY)
    end

    if ImGui.Button(ctx, label, width, 28) then clicked = true end

    ImGui.PopStyleColor(ctx, 5)
    ImGui.PopStyleVar(ctx, 1)
    return clicked
end

-- ==============================================================
-- CIRCLE OF FIFTHS WIDGET
-- ==============================================================
local function DrawCircleOfFifths(draw_list, cx, cy, outer_r, inner_r)
    local TAU = math.pi * 2
    local dpc = GetDiatonicPCs()
    local key_set = key_root_pc >= 0
    local seg_angle = TAU / 12

    -- Draw 12 arc segments
    for i = 1, 12 do
        local pc = cof_pc[i]
        local is_selected = (i == selected_cof_idx)
        local is_diatonic = (not key_set) or (dpc and dpc[pc])

        local start_angle = -math.pi / 2 + (i - 1) * seg_angle
        local end_angle   = start_angle + seg_angle
        local mid_angle   = (start_angle + end_angle) / 2

        -- Segment fill color
        local fill_col
        if is_selected then
            fill_col = 0x1A4B4FFF
        elseif key_set and not is_diatonic then
            fill_col = 0x1E2125FF  -- dimmed but opaque
        else
            fill_col = 0x25282BFF
        end

        -- Draw filled donut segment using quad fans
        local steps = 10
        for s = 0, steps - 1 do
            local a0 = start_angle + seg_angle * s / steps
            local a1 = start_angle + seg_angle * (s + 1) / steps
            local ox0 = cx + math.cos(a0) * outer_r
            local oy0 = cy + math.sin(a0) * outer_r
            local ox1 = cx + math.cos(a1) * outer_r
            local oy1 = cy + math.sin(a1) * outer_r
            local ix0 = cx + math.cos(a0) * inner_r
            local iy0 = cy + math.sin(a0) * inner_r
            local ix1 = cx + math.cos(a1) * inner_r
            local iy1 = cy + math.sin(a1) * inner_r
            ImGui.DrawList_AddQuadFilled(draw_list, ox0, oy0, ox1, oy1, ix1, iy1, ix0, iy0, fill_col)
        end

        -- Draw outer arc border using PathArcTo + PathStroke
        local border_col
        if is_selected then
            border_col = 0x215C61FF
        elseif key_set and is_diatonic then
            border_col = 0xD4A838AA
        else
            border_col = 0x3A3530FF
        end

        ImGui.DrawList_PathClear(draw_list)
        ImGui.DrawList_PathArcTo(draw_list, cx, cy, outer_r, start_angle + 0.02, end_angle - 0.02, 8)
        ImGui.DrawList_PathStroke(draw_list, border_col, 0, 1.5)

        ImGui.DrawList_PathClear(draw_list)
        ImGui.DrawList_PathArcTo(draw_list, cx, cy, inner_r, start_angle + 0.02, end_angle - 0.02, 8)
        ImGui.DrawList_PathStroke(draw_list, border_col, 0, 1.5)

        -- Radial divider lines between segments
        local div_col = 0x1A1C1EFF
        local lox = cx + math.cos(start_angle) * outer_r
        local loy = cy + math.sin(start_angle) * outer_r
        local lix = cx + math.cos(start_angle) * inner_r
        local liy = cy + math.sin(start_angle) * inner_r
        ImGui.DrawList_AddLine(draw_list, lox, loy, lix, liy, div_col, 1.5)

        -- Note label (centered in segment)
        local label = cof_roots[i]
        local label_r = (outer_r + inner_r) / 2
        local lx = cx + math.cos(mid_angle) * label_r
        local ly = cy + math.sin(mid_angle) * label_r
        local text_col
        if is_selected then
            text_col = 0xF3EBE1FF
        elseif key_set and not is_diatonic then
            text_col = 0x6A6460FF  -- readable but clearly de-emphasised
        elseif key_set and is_diatonic then
            text_col = 0xD4A838FF
        else
            text_col = 0xC4BDB5FF
        end
        local tw = #label * 7
        ImGui.DrawList_AddText(draw_list, lx - tw / 2, ly - 7, text_col, label)
    end

    -- Center hole fill
    ImGui.DrawList_AddCircleFilled(draw_list, cx, cy, inner_r - 1, 0x1A1C1EFF, 32)
end

local function CircleOfFifthsWidget(size)
    -- Returns true if a new root was clicked
    local clicked = false
    local outer_r = size / 2
    local inner_r = outer_r * 0.45

    local pos_x, pos_y = ImGui.GetCursorScreenPos(ctx)
    local cx = pos_x + outer_r
    local cy = pos_y + outer_r

    local draw_list = ImGui.GetWindowDrawList(ctx)
    DrawCircleOfFifths(draw_list, cx, cy, outer_r, inner_r)

    -- Invisible clickable area
    ImGui.InvisibleButton(ctx, "##cof", size, size)
    if ImGui.IsItemClicked(ctx) then
        -- Determine which segment was clicked
        local mx, my = ImGui.GetMousePos(ctx)
        local dx = mx - cx
        local dy = my - cy
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist >= inner_r and dist <= outer_r then
            local TAU = math.pi * 2
            local angle = math.atan(dy, dx) + math.pi / 2  -- offset so top=0
            if angle < 0 then angle = angle + TAU end
            local seg = math.floor(angle / (TAU / 12)) + 1
            if seg >= 1 and seg <= 12 then
                selected_cof_idx = seg
                clicked = true
            end
        end
    end
    return clicked
end

-- ==============================================================
-- CHORD BUILDER HELPERS
-- ==============================================================
local function BuildChordName()
    local root = cof_roots[selected_cof_idx]
    local qual = base_qualities[selected_quality_idx]
    local qi   = selected_quality_idx

    -- Build the 7th/extension part of the name independently of quality
    local ext_part = ""
    if sel_nat_ext >= 3 then
        ext_part = (sel_seventh == 2) and "maj13" or "13"
    elseif sel_nat_ext >= 2 then
        ext_part = (sel_seventh == 2) and "maj11" or "11"
    elseif sel_nat_ext >= 1 then
        ext_part = (sel_seventh == 2) and "maj9" or "9"
    elseif sel_seventh > 0 then
        ext_part = SEVENTH_LABELS[sel_seventh]
    end

    -- Alterations always appended after extension
    local alt_part = ""
    if sel_alt_b9  then alt_part = alt_part .. "b9"  end
    if sel_alt_s9  then alt_part = alt_part .. "#9"  end
    if sel_alt_s11 then alt_part = alt_part .. "#11" end
    if sel_alt_b13 then alt_part = alt_part .. "b13" end

    -- Assemble with quality-specific rules
    local name
    if qi == 5 or qi == 6 then
        -- Sus2 (qi=5) or Sus4 (qi=6): extension goes BEFORE "sus"
        -- Correct: C7sus4, Cmaj9sus2, C9sus4 — NOT Csus47
        name = root .. ext_part .. qual.short .. alt_part
    elseif qi == 3 and sel_seventh == 3 then
        -- Dim quality + dim7: absorb "dim" into "dim7" → "Cdim7" not "Cdimdim7"
        name = root .. "dim7" .. alt_part
    else
        -- Standard: root + quality_short + ext_part + alterations
        name = root .. qual.short .. ext_part .. alt_part
    end

    -- Slash bass note
    if selected_bass_idx > 0 then
        name = name .. "/" .. cof_roots[selected_bass_idx]
    end
    return name
end

local function BuildIntervals()
    local qual = base_qualities[selected_quality_idx]
    local intervals = {}
    for _, v in ipairs(qual.intervals) do table.insert(intervals, v) end
    -- 7th
    if sel_seventh > 0 then
        table.insert(intervals, SEVENTH_INTERVALS[sel_seventh])
    end
    -- Natural extensions (each implies all below it)
    if sel_nat_ext >= 1 then table.insert(intervals, 14) end -- 9th
    if sel_nat_ext >= 2 then table.insert(intervals, 17) end -- 11th
    if sel_nat_ext >= 3 then table.insert(intervals, 21) end -- 13th
    -- Alterations
    if sel_alt_b9  then table.insert(intervals, 13) end
    if sel_alt_s9  then table.insert(intervals, 15) end
    if sel_alt_s11 then table.insert(intervals, 18) end
    if sel_alt_b13 then table.insert(intervals, 20) end
    return intervals
end

-- ==============================================================
-- COLOR HELPER
-- ==============================================================
local function GetNativeColor(imgui_color)
    return r.ImGui_ColorConvertNative(imgui_color) | 0x1000000
end

-- ==============================================================
-- UPDATE ALL ITEM COLORS
-- ==============================================================
function UpdateAllColors()
    local native_color = GetNativeColor(current_track_color)
    local parent_track, child_track = nil, nil
    for i = 0, r.CountTracks(0) - 1 do
        local t = r.GetTrack(0, i)
        local _, name = r.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
        if name == "Chord Track" then parent_track = t
        elseif name == "Chord MIDI (Hidden)" then child_track = t end
    end
    if parent_track then
        r.SetMediaTrackInfo_Value(parent_track, "I_CUSTOMCOLOR", native_color)
        for i = 0, r.CountTrackMediaItems(parent_track) - 1 do
            r.SetMediaItemInfo_Value(r.GetTrackMediaItem(parent_track, i), "I_CUSTOMCOLOR", native_color)
        end
    end
    if child_track then
        r.SetMediaTrackInfo_Value(child_track, "I_CUSTOMCOLOR", native_color)
        for i = 0, r.CountTrackMediaItems(child_track) - 1 do
            r.SetMediaItemInfo_Value(r.GetTrackMediaItem(child_track, i), "I_CUSTOMCOLOR", native_color)
        end
    end
    r.UpdateArrange()
end

-- ==============================================================
-- TRACK CREATION
-- ==============================================================
function GetOrCreateChordTracks()
    local parent_track, child_track = nil, nil
    for i = 0, r.CountTracks(0) - 1 do
        local t = r.GetTrack(0, i)
        local _, name = r.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
        if name == "Chord Track" then parent_track = t
        elseif name == "Chord MIDI (Hidden)" then child_track = t end
    end
    local is_new = false
    local native_color = GetNativeColor(current_track_color)

    if not parent_track then
        is_new = true
        r.InsertTrackAtIndex(0, true)
        parent_track = r.GetTrack(0, 0)
        r.GetSetMediaTrackInfo_String(parent_track, "P_NAME", "Chord Track", true)
        r.SetMediaTrackInfo_Value(parent_track, "I_CUSTOMCOLOR", native_color)
        r.SetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH", 1)
    end
    if not child_track then
        local parent_idx = r.CSurf_TrackToID(parent_track, false)
        r.InsertTrackAtIndex(parent_idx, true)
        child_track = r.GetTrack(0, parent_idx)
        r.GetSetMediaTrackInfo_String(child_track, "P_NAME", "Chord MIDI (Hidden)", true)
        r.SetMediaTrackInfo_Value(child_track, "I_CUSTOMCOLOR", native_color)
        r.SetMediaTrackInfo_Value(child_track, "I_FOLDERDEPTH", -1)
        r.SetMediaTrackInfo_Value(child_track, "B_SHOWINTCP", 0)
        r.SetMediaTrackInfo_Value(child_track, "B_SHOWINMIXER", 0)
    end

    if is_new then
        r.SetOnlyTrackSelected(parent_track)
        r.SetTrackSelected(child_track, true)
        r.ReorderSelectedTracks(0, 0)
        local user_choice = r.ShowMessageBox("Pin chord track on top?", "AikyaLabs Simple ChordTrack", 4)
        if user_choice == 6 then
            r.Main_OnCommand(40000, 0)
            track_pinned = true
        else
            track_pinned = false
        end
    end
    return parent_track, child_track
end

-- ==============================================================
-- PIN HELPER
-- ==============================================================
local function SetPinState(should_pin)
    local parent_track, child_track = nil, nil
    for i = 0, r.CountTracks(0) - 1 do
        local t = r.GetTrack(0, i)
        local _, name = r.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
        if name == "Chord Track" then parent_track = t
        elseif name == "Chord MIDI (Hidden)" then child_track = t end
    end
    if not parent_track then return end
    -- Select only the chord tracks, then toggle pin
    local prev_sel = {}
    for i = 0, r.CountTracks(0) - 1 do
        local t = r.GetTrack(0, i)
        if r.IsTrackSelected(t) then table.insert(prev_sel, t) end
        r.SetTrackSelected(t, false)
    end
    r.SetTrackSelected(parent_track, true)
    if child_track then r.SetTrackSelected(child_track, true) end
    -- Action 40000 = Toggle pin — only fire if current state differs
    r.Main_OnCommand(40000, 0)
    track_pinned = should_pin
    -- Restore previous selection
    for _, t in ipairs(prev_sel) do r.SetTrackSelected(t, true) end
end

-- ==============================================================
-- INSERT CHORD
-- ==============================================================
local function GetNextFreeGroupID()
    local max_group = 0
    for i = 0, r.CountMediaItems(0) - 1 do
        local item  = r.GetMediaItem(0, i)
        local group = r.GetMediaItemInfo_Value(item, "I_GROUPID")
        if group > max_group then max_group = group end
    end
    return max_group + 1
end

function InsertChord()
    local parent_track, child_track = GetOrCreateChordTracks()

    -- Build intervals
    local root_pc    = cof_pc[selected_cof_idx]
    local base_midi  = (selected_octave + 1) * 12 + root_pc
    local chord_name = BuildChordName()
    local intervals  = BuildIntervals()

    r.Undo_BeginBlock()
    local target_regions = {}
    local items_to_delete = {}

    for i = 0, r.CountSelectedMediaItems(0) - 1 do
        local item  = r.GetSelectedMediaItem(0, i)
        local track = r.GetMediaItem_Track(item)
        if track == parent_track then
            local p = r.GetMediaItemInfo_Value(item, "D_POSITION")
            local l = r.GetMediaItemInfo_Value(item, "D_LENGTH")
            table.insert(target_regions, {pos = p, end_pos = p + l})
            table.insert(items_to_delete, item)
            for j = 0, r.CountTrackMediaItems(child_track) - 1 do
                local c_item = r.GetTrackMediaItem(child_track, j)
                local c_pos  = r.GetMediaItemInfo_Value(c_item, "D_POSITION")
                local c_len  = r.GetMediaItemInfo_Value(c_item, "D_LENGTH")
                if math.abs(c_pos - p) < 0.001 and math.abs(c_len - l) < 0.001 then
                    table.insert(items_to_delete, c_item)
                end
            end
        end
    end

    if #target_regions == 0 then
        local p = r.GetCursorPosition()
        local timesig_num, timesig_denom, _ = r.TimeMap_GetTimeSigAtTime(0, p)
        local length_qn = (timesig_num * 4) / timesig_denom * selected_duration
        local qn = r.TimeMap2_timeToQN(0, p)
        local ep = r.TimeMap2_QNToTime(0, qn + length_qn)
        table.insert(target_regions, {pos = p, end_pos = ep})
    end

    for _, item in ipairs(items_to_delete) do
        r.DeleteTrackMediaItem(r.GetMediaItem_Track(item), item)
    end

    local item_color = GetNativeColor(current_track_color)

    for _, region in ipairs(target_regions) do
        local pos     = region.pos
        local end_pos = region.end_pos

        -- Visible chord item (label only)
        local empty_item = r.AddMediaItemToTrack(parent_track)
        r.SetMediaItemPosition(empty_item, pos, false)
        r.SetMediaItemLength(empty_item, end_pos - pos, false)
        r.GetSetMediaItemInfo_String(empty_item, "P_NOTES", chord_name, true)
        r.SetMediaItemInfo_Value(empty_item, "I_CUSTOMCOLOR", item_color)

        local _, chunk = r.GetItemStateChunk(empty_item, "", false)
        if not chunk:match("IMGRESOURCEFLAGS") then
            chunk = chunk:gsub(">\n?$", "IMGRESOURCEFLAGS 2\n>")
        else
            chunk = chunk:gsub("IMGRESOURCEFLAGS %d+", "IMGRESOURCEFLAGS 2")
        end
        r.SetItemStateChunk(empty_item, chunk, false)

        -- MIDI chord item
        local midi_item = r.CreateNewMIDIItemInProj(child_track, pos, end_pos, false)
        local take      = r.GetActiveTake(midi_item)
        r.GetSetMediaItemTakeInfo_String(take, "P_NAME", chord_name, true)
        r.SetMediaItemInfo_Value(midi_item, "I_CUSTOMCOLOR", item_color)

        local ppq_pos = r.MIDI_GetPPQPosFromProjTime(take, pos)
        local ppq_end = r.MIDI_GetPPQPosFromProjTime(take, end_pos)

        -- Bass note: octave 2 (MIDI 36-47 range), always below chord
        if selected_bass_idx > 0 then
            local bass_pc   = cof_pc[selected_bass_idx]
            local bass_midi = 36 + bass_pc  -- C2=36 as anchor
            -- If bass >= root at same octave, push it down
            if bass_midi >= base_midi then bass_midi = bass_midi - 12 end
            r.MIDI_InsertNote(take, true, false, ppq_pos, ppq_end, 0, math.max(0, bass_midi), 100, true)
        end

        -- Chord notes
        for _, interval in ipairs(intervals) do
            local note = math.min(127, base_midi + interval)
            r.MIDI_InsertNote(take, true, false, ppq_pos, ppq_end, 0, note, 100, true)
        end
        r.MIDI_Sort(take)

        local group_id = GetNextFreeGroupID()
        r.SetMediaItemInfo_Value(empty_item, "I_GROUPID", group_id)
        r.SetMediaItemInfo_Value(midi_item, "I_GROUPID", group_id)
    end

    if #target_regions > 0 then
        local max_end = 0
        for _, region in ipairs(target_regions) do
            if region.end_pos > max_end then max_end = region.end_pos end
        end
        r.SetEditCurPos(max_end, true, true)
    end

    r.UpdateArrange()
    r.Undo_EndBlock("Insert Chord: " .. chord_name, -1)
end

-- ==============================================================
-- CLEANUP ORPHANS
-- ==============================================================
function CleanupOrphanedChords()
    local parent_track, child_track = nil, nil
    for i = 0, r.CountTracks(0) - 1 do
        local t = r.GetTrack(0, i)
        local _, name = r.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
        if name == "Chord Track" then parent_track = t
        elseif name == "Chord MIDI (Hidden)" then child_track = t end
    end
    if not parent_track or not child_track then return end
    local orphans = {}
    for i = 0, r.CountTrackMediaItems(child_track) - 1 do
        local c_item  = r.GetTrackMediaItem(child_track, i)
        local c_pos   = r.GetMediaItemInfo_Value(c_item, "D_POSITION")
        local c_len   = r.GetMediaItemInfo_Value(c_item, "D_LENGTH")
        local c_group = r.GetMediaItemInfo_Value(c_item, "I_GROUPID")
        local is_orphan = true
        if c_group > 0 then
            for j = 0, r.CountTrackMediaItems(parent_track) - 1 do
                local p_item = r.GetTrackMediaItem(parent_track, j)
                if r.GetMediaItemInfo_Value(p_item, "I_GROUPID") == c_group then
                    is_orphan = false; break
                end
            end
        else
            for j = 0, r.CountTrackMediaItems(parent_track) - 1 do
                local p_item = r.GetTrackMediaItem(parent_track, j)
                local p_pos  = r.GetMediaItemInfo_Value(p_item, "D_POSITION")
                local p_len  = r.GetMediaItemInfo_Value(p_item, "D_LENGTH")
                if math.abs(p_pos - c_pos) < 0.001 and math.abs(p_len - c_len) < 0.001 then
                    is_orphan = false; break
                end
            end
        end
        if is_orphan then table.insert(orphans, c_item) end
    end
    if #orphans > 0 then
        for _, item in ipairs(orphans) do r.DeleteTrackMediaItem(child_track, item) end
        r.UpdateArrange()
    end
end

-- ==============================================================
-- DISPLAY TAB: GET CURRENT & NEXT CHORDS
-- ==============================================================
local function GetCurrentAndNextChords()
    local parent_track = nil
    for i = 0, r.CountTracks(0) - 1 do
        local t = r.GetTrack(0, i)
        local _, name = r.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
        if name == "Chord Track" then parent_track = t; break end
    end
    if not parent_track then return nil, nil, 0 end

    local play_state = r.GetPlayState()
    local time = (play_state == 1 or play_state == 5) and r.GetPlayPosition() or r.GetCursorPosition()

    local current_chord, next_chord, progress = nil, nil, 0
    local num_items = r.CountTrackMediaItems(parent_track)
    for i = 0, num_items - 1 do
        local item    = r.GetTrackMediaItem(parent_track, i)
        local pos     = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local len     = r.GetMediaItemInfo_Value(item, "D_LENGTH")
        local end_pos = pos + len
        if time >= pos and time < end_pos then
            _, current_chord = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
            progress = (time - pos) / len
            if i + 1 < num_items then
                local ni = r.GetTrackMediaItem(parent_track, i + 1)
                _, next_chord = r.GetSetMediaItemInfo_String(ni, "P_NOTES", "", false)
            end
            break
        elseif time < pos then
            _, next_chord = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
            break
        end
    end
    return current_chord, next_chord, progress
end

-- ==============================================================
-- MAIN LOOP
-- ==============================================================
local last_proj_change_count = r.GetProjectStateChangeCount(0)

function loop()
    local current_change_count = r.GetProjectStateChangeCount(0)
    if current_change_count ~= last_proj_change_count then
        CleanupOrphanedChords()
        last_proj_change_count = r.GetProjectStateChangeCount(0)
    end

    ImGui.PushFont(ctx, font_main)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 16, 16)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 6, 6)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 0)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, C_BG_DARK)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, C_TEXT_PRIMARY)

    local pop_colors = 2
    if ImGui.Col_Tab then
        ImGui.PushStyleColor(ctx, ImGui.Col_Tab, C_BG_SURFACE)
        ImGui.PushStyleColor(ctx, ImGui.Col_TabHovered, C_UI_TEAL_HOVER)
        ImGui.PushStyleColor(ctx, ImGui.Col_TabActive, C_UI_TEAL)
        pop_colors = pop_colors + 3
    end

    ImGui.SetNextWindowSizeConstraints(ctx, 900, 420, 4000, 4000)
    ImGui.SetNextWindowSize(ctx, 960, 460, ImGui.Cond_Appearing)

    local visible, open = ImGui.Begin(ctx, 'AikyaLabs Simple ChordTrack', true)
    if visible then

        local window_w = ImGui.GetWindowWidth(ctx)
        local key_set  = key_root_pc >= 0

        -- Logo + brand on left
        ImGui.BeginGroup(ctx)
            ImGui.Dummy(ctx, 0, 10)
            if logo_img then
                ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + 15)
                ImGui.Image(ctx, logo_img, 70, 70)
                ImGui.Dummy(ctx, 0, 4)
            end
            ImGui.TextColored(ctx, C_TEXT_PRIMARY, "AIKYA LABS")
        ImGui.EndGroup(ctx)

        ImGui.SameLine(ctx, 0, 30)

        ImGui.BeginGroup(ctx)
            if ImGui.BeginTabBar(ctx, "MainTabs") then

                -- ============================================================
                -- EDITOR TAB
                -- ============================================================
                if ImGui.BeginTabItem(ctx, "Editor") then
                    ImGui.Dummy(ctx, 0, 8)

                    -- COL 1: Circle of Fifths + Octave
                    local cof_size = 170
                    ImGui.BeginChild(ctx, "Col1", cof_size + 10, 0)
                        ImGui.TextColored(ctx, C_TEXT_SECONDARY, "ROOT NOTE")
                        ImGui.Dummy(ctx, 0, 4)
                        CircleOfFifthsWidget(cof_size)
                        ImGui.Dummy(ctx, 0, 8)
                        ImGui.TextColored(ctx, C_TEXT_SECONDARY, "OCTAVE")
                        ImGui.SetNextItemWidth(ctx, cof_size)
                        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, C_BG_SURFACE)
                        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, C_BG_SURFACE)
                        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, C_BG_SURFACE)
                        ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab, C_UI_TEAL)
                        ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive, C_UI_TEAL_ACTIVE)
                        local rv, new_oct = ImGui.SliderInt(ctx, "##Octave", selected_octave, 1, 5, "Oct %d")
                        if rv then selected_octave = new_oct end
                        ImGui.PopStyleColor(ctx, 5)
                    ImGui.EndChild(ctx)

                    ImGui.SameLine(ctx, 0, 16)

                    -- COL 2: Base Qualities + Structured Tensions
                    ImGui.BeginChild(ctx, "Col2", 250, 0)
                        -- Base qualities
                        ImGui.TextColored(ctx, C_TEXT_SECONDARY, "CHORD QUALITY")
                        ImGui.Dummy(ctx, 0, 4)
                        local q_btn_w = 75
                        for i, q in ipairs(base_qualities) do
                            if i > 1 and (i - 1) % 3 ~= 0 then ImGui.SameLine(ctx) end
                            local is_diatonic = IsQualityDiatonic(i)
                            if DiatonicToggleButton(q.name, selected_quality_idx == i, q_btn_w, is_diatonic, key_set) then
                                selected_quality_idx = i
                                -- Reset extensions when quality changes
                                sel_seventh = 0; sel_nat_ext = 0
                                sel_alt_b9 = false; sel_alt_s9 = false
                                sel_alt_s11 = false; sel_alt_b13 = false
                            end
                        end

                        ImGui.Dummy(ctx, 0, 10)

                        -- SEVENTH (mutually exclusive radio row)
                        ImGui.TextColored(ctx, C_TEXT_SECONDARY, "SEVENTH")
                        ImGui.Dummy(ctx, 0, 4)
                        local seventh_options = {{"None",0},{"7",1},{"maj7",2},{"dim7",3}}
                        for si, sv in ipairs(seventh_options) do
                            if si > 1 then ImGui.SameLine(ctx) end
                            local is7_diatonic = (sv[2] == 0) or IsIntervalDiatonic(SEVENTH_INTERVALS[sv[2]])
                            local dim7 = key_set and sv[2] > 0 and not is7_diatonic
                            if ToggleButton(sv[1], sel_seventh == sv[2], 54, 26, dim7) then
                                if sel_seventh == sv[2] then
                                    sel_seventh = 0; sel_nat_ext = 0  -- deselect clears extensions
                                else
                                    sel_seventh = sv[2]
                                    -- dim7 cannot have natural extensions — clear them
                                    if sv[2] == 3 then
                                        sel_nat_ext = 0
                                        sel_alt_b9 = false; sel_alt_s9 = false
                                        sel_alt_s11 = false; sel_alt_b13 = false
                                    end
                                end
                                -- Alterations require a 7th — clear if removing 7th
                                if sel_seventh == 0 then
                                    sel_nat_ext = 0
                                    sel_alt_b9 = false; sel_alt_s9 = false
                                    sel_alt_s11 = false; sel_alt_b13 = false
                                end
                            end
                        end

                        ImGui.Dummy(ctx, 0, 10)

                        -- NATURAL EXTENSIONS (hierarchical — each requires prior)
                        -- Rules: 9 blocked if b9 or #9 active; 11 blocked if #11 active; 13 blocked if b13 active
                        ImGui.TextColored(ctx, C_TEXT_SECONDARY, "EXTENSION")
                        ImGui.Dummy(ctx, 0, 4)
                        local ext_labels    = {"9", "11", "13"}
                        local ext_intervals = {14,  17,  21}
                        -- Per-button availability: blocked by conflicting alteration OR missing prerequisite
                        local ext_blocked = {
                            sel_alt_b9 or sel_alt_s9,            -- 9 blocked if b9 or #9 active
                            sel_alt_s11,                          -- 11 blocked if #11 active
                            sel_alt_b13,                          -- 13 blocked if b13 active
                        }
                        for ei = 1, 3 do
                            if ei > 1 then ImGui.SameLine(ctx) end
                            -- Prerequisites: need 7th (not dim7), and each step must have previous
                            local has_prereq = sel_seventh > 0 and sel_seventh ~= 3 and (ei == 1 or sel_nat_ext >= ei - 1)
                            local blocked    = ext_blocked[ei] or not has_prereq
                            local active     = sel_nat_ext >= ei
                            local is_diatonic = IsIntervalDiatonic(ext_intervals[ei])
                            local dim = blocked and not active
                            if key_set and not is_diatonic and not active then dim = true end
                            if ToggleButton(ext_labels[ei], active, 60, 26, dim) then
                                if not blocked then
                                    if active then
                                        sel_nat_ext = ei - 1  -- collapse back
                                        -- Clear alterations that only made sense at the removed level.
                                        -- When collapsing to below 9 (ei=1), clear all alterations.
                                        -- When collapsing to below 11 (ei=2), clear #11.
                                        -- When collapsing to below 13 (ei=3), clear b13.
                                        if ei >= 1 then sel_alt_b13 = false end
                                        if ei >= 1 then sel_alt_s11 = false end
                                        if ei <= 1 then sel_alt_b9 = false; sel_alt_s9 = false end
                                    else
                                        sel_nat_ext = ei
                                    end
                                end
                            end
                        end

                        ImGui.Dummy(ctx, 0, 10)

                        -- ALTERATIONS (require a 7th; each blocked by the natural extension at the same degree)
                        -- b9/natural-9, #9/natural-9 = mutually exclusive (can't have natural AND altered 9)
                        -- b9 and #9 = mutually exclusive with each other
                        -- #11 and natural-11 = mutually exclusive
                        -- b13 and natural-13 = mutually exclusive
                        ImGui.TextColored(ctx, C_TEXT_SECONDARY, "ALTERATIONS")
                        ImGui.Dummy(ctx, 0, 4)
                        local need_7th = sel_seventh > 0
                        -- Availability per alteration:
                        local alt_data = {
                            -- {label, current_state, compound_interval, blocked_by}
                            {"b9",  sel_alt_b9,  13, not need_7th or sel_nat_ext >= 1 or sel_alt_s9  },
                            {"#9",  sel_alt_s9,  15, not need_7th or sel_nat_ext >= 1 or sel_alt_b9  },
                            {"#11", sel_alt_s11, 18, not need_7th or sel_nat_ext >= 2                 },
                            {"b13", sel_alt_b13, 20, not need_7th or sel_nat_ext >= 3                 },
                        }
                        for ai, av in ipairs(alt_data) do
                            if ai > 1 then ImGui.SameLine(ctx) end
                            local label     = av[1]
                            local state     = av[2]
                            local compound  = av[3]
                            local blocked   = av[4]
                            local is_diatonic = IsIntervalDiatonic(compound)
                            local dim = (blocked and not state) or (key_set and not is_diatonic and not state)
                            if ToggleButton(label, state, 52, 26, dim) then
                                if not blocked then
                                    if ai == 1 then sel_alt_b9  = not sel_alt_b9
                                    elseif ai == 2 then sel_alt_s9  = not sel_alt_s9
                                    elseif ai == 3 then sel_alt_s11 = not sel_alt_s11
                                    elseif ai == 4 then sel_alt_b13 = not sel_alt_b13 end
                                end
                            end
                        end

                        -- Clear all button
                        local has_any = sel_seventh > 0 or sel_nat_ext > 0 or sel_alt_b9 or sel_alt_s9 or sel_alt_s11 or sel_alt_b13
                        if has_any then
                            ImGui.Dummy(ctx, 0, 6)
                            ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x3A2218FF)
                            ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x4A2A20FF)
                            ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x2A1810FF)
                            ImGui.PushStyleColor(ctx, ImGui.Col_Text, C_TEXT_SECONDARY)
                            ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 0)
                            if ImGui.Button(ctx, "Clear All", -1, 22) then
                                sel_seventh = 0; sel_nat_ext = 0
                                sel_alt_b9 = false; sel_alt_s9 = false
                                sel_alt_s11 = false; sel_alt_b13 = false
                            end
                            ImGui.PopStyleVar(ctx, 1)
                            ImGui.PopStyleColor(ctx, 4)
                        end
                    ImGui.EndChild(ctx)

                    ImGui.SameLine(ctx, 0, 16)

                    -- COL 3: Preview + Insert
                    ImGui.BeginChild(ctx, "Col3", 0, 0)
                        ImGui.Dummy(ctx, 0, 16)
                        local preview_str = BuildChordName()
                        ImGui.TextColored(ctx, C_TEXT_SECONDARY, "READY TO INSERT:")
                        ImGui.PushFont(ctx, font_h2)
                        ImGui.TextColored(ctx, C_TEXT_PRIMARY, preview_str)
                        ImGui.PopFont(ctx)

                        ImGui.Dummy(ctx, 0, 12)

                        -- Duration selector
                        ImGui.TextColored(ctx, C_TEXT_SECONDARY, "DURATION")
                        ImGui.Dummy(ctx, 0, 4)
                        local durations = {0.5, 1.0, 2.0, 4.0}
                        local dur_labels = {" 1/2 ", "  1  ", "  2  ", "  4  "}
                        for di, dv in ipairs(durations) do
                            if di > 1 then ImGui.SameLine(ctx) end
                            if ToggleButton(dur_labels[di], selected_duration == dv, 48, 26) then
                                selected_duration = dv
                            end
                        end

                        ImGui.Dummy(ctx, 0, 16)

                        ImGui.PushStyleColor(ctx, ImGui.Col_Button, C_CTA_BRICK)
                        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C_CTA_HOVER)
                        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C_CTA_ACTIVE)
                        ImGui.PushStyleColor(ctx, ImGui.Col_Text, C_TEXT_PRIMARY)
                        ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 0)
                        if ImGui.Button(ctx, "INSERT CHORD", -1, 60) then InsertChord() end
                        ImGui.PopStyleVar(ctx, 1)
                        ImGui.PopStyleColor(ctx, 4)
                    ImGui.EndChild(ctx)

                    -- FULL-WIDTH ROWS BELOW COLUMNS
                    ImGui.Dummy(ctx, 0, 10)

                    -- Bass note row
                    local avail_w = window_w - 150
                    ImGui.TextColored(ctx, C_TEXT_SECONDARY, "BASS NOTE (SLASH CHORD)")
                    ImGui.Dummy(ctx, 0, 4)
                    local bass_btn_w = math.max(38, math.floor((avail_w - 70) / 13))
                    if ToggleButton("None", selected_bass_idx == 0, 50) then selected_bass_idx = 0 end
                    for i = 1, 12 do
                        ImGui.SameLine(ctx)
                        local is_diatonic_bass = IsRootDiatonic(cof_pc[i])
                        local dim_bass = key_set and not is_diatonic_bass
                        if ToggleButton(cof_roots[i], selected_bass_idx == i, bass_btn_w, 26, dim_bass) then
                            selected_bass_idx = (selected_bass_idx == i) and 0 or i
                        end
                    end

                    ImGui.EndTabItem(ctx)
                end

                -- ============================================================
                -- DISPLAY TAB
                -- ============================================================
                if ImGui.BeginTabItem(ctx, "Display") then
                    local current_chord, next_chord, progress = GetCurrentAndNextChords()
                    ImGui.Dummy(ctx, 0, 20)
                    ImGui.BeginChild(ctx, "DispTop", 0, 160)
                        ImGui.BeginChild(ctx, "DispCol1", (window_w - 200) * 0.55, 0)
                            local c_chord_str = current_chord or "---"
                            ImGui.PushFont(ctx, font_h1)
                            local cc_w, _ = ImGui.CalcTextSize(ctx, c_chord_str)
                            ImGui.SetCursorPosX(ctx, (ImGui.GetWindowWidth(ctx) - cc_w) / 2)
                            ImGui.SetCursorPosY(ctx, 40)
                            ImGui.TextColored(ctx, C_TEXT_PRIMARY, c_chord_str)
                            ImGui.PopFont(ctx)
                        ImGui.EndChild(ctx)
                        ImGui.SameLine(ctx, 0, 30)
                        ImGui.BeginChild(ctx, "DispCol2", 0, 0)
                            ImGui.Dummy(ctx, 0, 40)
                            local n_chord_val = next_chord or "---"
                            ImGui.PushFont(ctx, font_h2)
                            ImGui.TextColored(ctx, C_TEXT_SECONDARY, "NEXT: " .. n_chord_val)
                            ImGui.PopFont(ctx)
                        ImGui.EndChild(ctx)
                    ImGui.EndChild(ctx)
                    ImGui.Dummy(ctx, 0, 10)
                    ImGui.PushStyleColor(ctx, ImGui.Col_PlotHistogram, C_CTA_BRICK)
                    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, C_BG_SURFACE)
                    ImGui.ProgressBar(ctx, progress, -1, 16, "")
                    ImGui.PopStyleColor(ctx, 2)
                    ImGui.EndTabItem(ctx)
                end

                -- ============================================================
                -- SETTINGS TAB
                -- ============================================================
                if ImGui.BeginTabItem(ctx, "Settings") then
                    ImGui.Dummy(ctx, 0, 16)

                    -- KEY / SCALE AWARENESS
                    ImGui.TextColored(ctx, C_TEXT_SECONDARY, "KEY & SCALE AWARENESS")
                    ImGui.Dummy(ctx, 0, 8)

                    -- Key root dropdown (using cof_roots order for display)
                    local key_display = key_root_pc < 0 and "No Key Set" or cof_roots[pc_to_cof[key_root_pc]]
                    ImGui.SetNextItemWidth(ctx, 150)
                    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, C_BG_SURFACE)
                    ImGui.PushStyleColor(ctx, ImGui.Col_PopupBg, C_BG_SURFACE)
                    if ImGui.BeginCombo(ctx, "##KeyRoot", key_display) then
                        if ImGui.Selectable(ctx, "No Key Set", key_root_pc < 0) then
                            key_root_pc = -1
                        end
                        for i = 1, 12 do
                            local pc = cof_pc[i]
                            if ImGui.Selectable(ctx, cof_roots[i], key_root_pc == pc) then
                                key_root_pc = pc
                            end
                        end
                        ImGui.EndCombo(ctx)
                    end
                    ImGui.PopStyleColor(ctx, 2)

                    ImGui.SameLine(ctx)
                    ImGui.TextColored(ctx, C_TEXT_SECONDARY, "Root Key")

                    -- Scale type dropdown
                    ImGui.Dummy(ctx, 0, 6)
                    ImGui.SetNextItemWidth(ctx, 150)
                    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, C_BG_SURFACE)
                    ImGui.PushStyleColor(ctx, ImGui.Col_PopupBg, C_BG_SURFACE)
                    if ImGui.BeginCombo(ctx, "##ScaleType", scales[key_scale_idx].name) then
                        for i, scale in ipairs(scales) do
                            if ImGui.Selectable(ctx, scale.name, key_scale_idx == i) then
                                key_scale_idx = i
                            end
                        end
                        ImGui.EndCombo(ctx)
                    end
                    ImGui.PopStyleColor(ctx, 2)
                    ImGui.SameLine(ctx)
                    ImGui.TextColored(ctx, C_TEXT_SECONDARY, "Scale")

                    if key_root_pc >= 0 then
                        ImGui.Dummy(ctx, 0, 4)
                        local kname = cof_roots[pc_to_cof[key_root_pc]]
                        ImGui.PushFont(ctx, font_sm)
                        ImGui.TextColored(ctx, C_GOLD, "Active: " .. kname .. " " .. scales[key_scale_idx].name ..
                            "  •  Gold = diatonic  •  Dimmed = out of key")
                        ImGui.PopFont(ctx)
                    end

                    ImGui.Dummy(ctx, 0, 20)

                    -- TRACK BEHAVIOUR
                    ImGui.TextColored(ctx, C_TEXT_SECONDARY, "TRACK BEHAVIOUR")
                    ImGui.Dummy(ctx, 0, 8)
                    ImGui.PushStyleColor(ctx, ImGui.Col_CheckMark, C_UI_TEAL_HOVER)
                    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, C_BG_SURFACE)
                    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, 0x303438FF)
                    local pin_rv, new_pinned = ImGui.Checkbox(ctx, "Pin Chord Track to top of arrange view", track_pinned)
                    ImGui.PopStyleColor(ctx, 3)
                    if pin_rv then
                        SetPinState(new_pinned)
                    end

                    ImGui.Dummy(ctx, 0, 20)

                    -- CHORD TRACK APPEARANCE
                    ImGui.TextColored(ctx, C_TEXT_SECONDARY, "CHORD TRACK APPEARANCE")
                    ImGui.Dummy(ctx, 0, 8)
                    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 4)
                    local flags = ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_NoSidePreview
                    local rv, new_color = ImGui.ColorEdit3(ctx, "Track & Item Color", current_track_color, flags)
                    if rv then
                        current_track_color = new_color
                        r.SetExtState("AikyaLabs_ChordTrack", "TrackColor", tostring(new_color), true)
                        UpdateAllColors()
                    end
                    ImGui.PopStyleVar(ctx, 1)

                    ImGui.EndTabItem(ctx)
                end

                ImGui.EndTabBar(ctx)
            end
        ImGui.EndGroup(ctx)

        ImGui.End(ctx)
    end

    ImGui.PopStyleColor(ctx, pop_colors)
    ImGui.PopStyleVar(ctx, 4)
    ImGui.PopFont(ctx)

    if open then r.defer(loop) end
end

function init()
    GetOrCreateChordTracks()
    loop()
end

r.defer(init)
