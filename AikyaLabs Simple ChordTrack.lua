-- @description AikyaLabs Simple ChordTrack
-- @author Aikya Labs
-- @version 1.0.0
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

-- Font configuration using native shim
local font_main = ImGui.CreateFont('sans-serif', 15)
local font_h1 = ImGui.CreateFont('sans-serif', 80)
local font_h2 = ImGui.CreateFont('sans-serif', 24)

ImGui.Attach(ctx, font_main)
ImGui.Attach(ctx, font_h1)
ImGui.Attach(ctx, font_h2)

local script_path = debug.getinfo(1, 'S').source:match("@?(.*[\\/])") or ""
local logo_img = nil
if ImGui.CreateImage then
    logo_img = ImGui.CreateImage(script_path .. "logo_processed.png")
end

-- Data Definitions
local roots = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
local root_offsets = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}

local chord_groups = {
    {
        name = "Triads & Suspended",
        chords = {
            {name = "Major", short = "", intervals = {0, 4, 7}},
            {name = "Minor", short = "m", intervals = {0, 3, 7}},
            {name = "Dim", short = "dim", intervals = {0, 3, 6}},
            {name = "Aug", short = "aug", intervals = {0, 4, 8}},
            {name = "Sus2", short = "sus2", intervals = {0, 2, 7}},
            {name = "Sus4", short = "sus4", intervals = {0, 5, 7}}
        }
    },
    {
        name = "Sevenths & Extensions",
        chords = {
            {name = "Maj7", short = "maj7", intervals = {0, 4, 7, 11}},
            {name = "Min7", short = "m7", intervals = {0, 3, 7, 10}},
            {name = "Dom7", short = "7", intervals = {0, 4, 7, 10}},
            {name = "m7b5", short = "m7b5", intervals = {0, 3, 6, 10}},
            {name = "dim7", short = "dim7", intervals = {0, 3, 6, 9}},
            {name = "add9", short = "add9", intervals = {0, 4, 7, 14}},
            {name = "6", short = "6", intervals = {0, 4, 7, 9}},
            {name = "m6", short = "m6", intervals = {0, 3, 7, 9}}
        }
    }
}

local all_qualities = {}
for _, group in ipairs(chord_groups) do
    for _, q in ipairs(group.chords) do
        table.insert(all_qualities, q)
    end
end

-- State
local selected_root_idx = 1
local selected_quality_idx = 1
local selected_octave = 3

-- AIKYA LABS BRAND COLORS
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

local function ToggleButton(label, selected, width)
    local clicked = false
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 1)
    ImGui.PushStyleColor(ctx, ImGui.Col_Border, C_BORDER_BROWN)
    
    if selected then
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, C_UI_TEAL)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C_UI_TEAL_HOVER)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C_UI_TEAL_ACTIVE)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, C_TEXT_PRIMARY)
    else
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, C_BG_SURFACE)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x303438FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x1A1C1EFF)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, C_TEXT_SECONDARY)
    end
    
    if ImGui.Button(ctx, label, width, 28) then clicked = true end
    
    ImGui.PopStyleColor(ctx, 5)
    ImGui.PopStyleVar(ctx, 1)
    return clicked
end

function GetOrCreateChordTracks()
    local parent_track, child_track = nil, nil
    local track_count = r.CountTracks(0)
    for i = 0, track_count - 1 do
        local t = r.GetTrack(0, i)
        local _, name = r.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
        if name == "Chord Track" then parent_track = t
        elseif name == "Chord MIDI (Hidden)" then child_track = t end
    end
    if not parent_track then
        r.InsertTrackAtIndex(0, true)
        parent_track = r.GetTrack(0, 0)
        r.GetSetMediaTrackInfo_String(parent_track, "P_NAME", "Chord Track", true)
        r.SetMediaTrackInfo_Value(parent_track, "I_CUSTOMCOLOR", r.ColorToNative(26, 75, 79) | 0x1000000)
        r.SetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH", 1)
    end
    if not child_track then
        local parent_idx = r.CSurf_TrackToID(parent_track, false)
        r.InsertTrackAtIndex(parent_idx, true)
        child_track = r.GetTrack(0, parent_idx)
        r.GetSetMediaTrackInfo_String(child_track, "P_NAME", "Chord MIDI (Hidden)", true)
        r.SetMediaTrackInfo_Value(child_track, "I_CUSTOMCOLOR", r.ColorToNative(37, 40, 43) | 0x1000000)
        r.SetMediaTrackInfo_Value(child_track, "I_FOLDERDEPTH", -1)
        r.SetMediaTrackInfo_Value(child_track, "B_SHOWINTCP", 0)
        r.SetMediaTrackInfo_Value(child_track, "B_SHOWINMIXER", 0)
    end
    return parent_track, child_track
end

local function GetNextFreeGroupID()
    local max_group = 0
    for i = 0, r.CountMediaItems(0) - 1 do
        local item = r.GetMediaItem(0, i)
        local group = r.GetMediaItemInfo_Value(item, "I_GROUPID")
        if group > max_group then max_group = group end
    end
    return max_group + 1
end

function InsertChord()
    local parent_track, child_track = GetOrCreateChordTracks()
    local root_name = roots[selected_root_idx]
    local base_c = (selected_octave + 1) * 12 
    local root_note = base_c + root_offsets[selected_root_idx]
    local quality = all_qualities[selected_quality_idx]
    
    local chord_name = root_name .. quality.short
    
    r.Undo_BeginBlock()
    local target_regions = {}
    local items_to_delete = {}
    
    for i = 0, r.CountSelectedMediaItems(0) - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        local track = r.GetMediaItem_Track(item)
        if track == parent_track then
            local p = r.GetMediaItemInfo_Value(item, "D_POSITION")
            local l = r.GetMediaItemInfo_Value(item, "D_LENGTH")
            table.insert(target_regions, {pos = p, end_pos = p + l})
            table.insert(items_to_delete, item)
            
            for j = 0, r.CountTrackMediaItems(child_track) - 1 do
                local c_item = r.GetTrackMediaItem(child_track, j)
                local c_pos = r.GetMediaItemInfo_Value(c_item, "D_POSITION")
                local c_len = r.GetMediaItemInfo_Value(c_item, "D_LENGTH")
                if math.abs(c_pos - p) < 0.001 and math.abs(c_len - l) < 0.001 then
                    table.insert(items_to_delete, c_item)
                end
            end
        end
    end
    
    if #target_regions == 0 then
        local p = r.GetCursorPosition()
        local timesig_num, timesig_denom, _ = r.TimeMap_GetTimeSigAtTime(0, p)
        local length_qn = (timesig_num * 4) / timesig_denom
        local qn = r.TimeMap2_timeToQN(0, p)
        local ep = r.TimeMap2_QNToTime(0, qn + length_qn) 
        table.insert(target_regions, {pos = p, end_pos = ep})
    end
    
    for _, item in ipairs(items_to_delete) do
        local track = r.GetMediaItem_Track(item)
        r.DeleteTrackMediaItem(track, item)
    end
    
    local item_color = r.ColorToNative(180, 76, 54) | 0x1000000

    for _, region in ipairs(target_regions) do
        local pos = region.pos
        local end_pos = region.end_pos
        
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
        
        local midi_item = r.CreateNewMIDIItemInProj(child_track, pos, end_pos, false)
        local take = r.GetActiveTake(midi_item)
        r.GetSetMediaItemTakeInfo_String(take, "P_NAME", chord_name, true)
        r.SetMediaItemInfo_Value(midi_item, "I_CUSTOMCOLOR", item_color)
        
        local ppq_pos = r.MIDI_GetPPQPosFromProjTime(take, pos)
        local ppq_end = r.MIDI_GetPPQPosFromProjTime(take, end_pos)
        
        for _, interval in ipairs(quality.intervals) do
            local target_note = math.min(127, root_note + interval)
            r.MIDI_InsertNote(take, true, false, ppq_pos, ppq_end, 0, target_note, 100, true)
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
        local c_item = r.GetTrackMediaItem(child_track, i)
        local c_pos = r.GetMediaItemInfo_Value(c_item, "D_POSITION")
        local c_len = r.GetMediaItemInfo_Value(c_item, "D_LENGTH")
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
                local p_pos = r.GetMediaItemInfo_Value(p_item, "D_POSITION")
                local p_len = r.GetMediaItemInfo_Value(p_item, "D_LENGTH")
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
    
    local current_chord = nil
    local next_chord = nil
    local progress = 0
    
    local num_items = r.CountTrackMediaItems(parent_track)
    for i = 0, num_items - 1 do
        local item = r.GetTrackMediaItem(parent_track, i)
        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
        local end_pos = pos + len
        
        if time >= pos and time < end_pos then
            _, current_chord = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
            progress = (time - pos) / len
            if i + 1 < num_items then
                local next_item = r.GetTrackMediaItem(parent_track, i + 1)
                _, next_chord = r.GetSetMediaItemInfo_String(next_item, "P_NOTES", "", false)
            end
            break
        elseif time < pos then
            _, next_chord = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
            break
        end
    end
    return current_chord, next_chord, progress
end

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
    
    ImGui.SetNextWindowSizeConstraints(ctx, 800, 310, 4000, 4000)
    ImGui.SetNextWindowSize(ctx, 840, 320, ImGui.Cond_Appearing)
    
    local visible, open = ImGui.Begin(ctx, 'AikyaLabs Simple ChordTrack', true)
    if visible then
        
        local window_w = ImGui.GetWindowWidth(ctx)
        
        -- Global Layout: Logo Left, Content Right
        ImGui.BeginGroup(ctx)
            ImGui.Dummy(ctx, 0, 10)
            if logo_img then
                local target_size = 70
                ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + 15)
                ImGui.Image(ctx, logo_img, target_size, target_size)
                ImGui.Dummy(ctx, 0, 4)
            end
            local brand_text = "AIKYA LABS"
            ImGui.TextColored(ctx, C_TEXT_PRIMARY, brand_text)
        ImGui.EndGroup(ctx)
        
        ImGui.SameLine(ctx, 0, 30)
        
        ImGui.BeginGroup(ctx)
            if ImGui.BeginTabBar(ctx, "MainTabs") then
                
                -- ==========================================
                -- EDITOR TAB
                -- ==========================================
                if ImGui.BeginTabItem(ctx, "Editor") then
                    ImGui.Dummy(ctx, 0, 8)
                    
                    -- COLUMN 1: ROOT & OCTAVE
                    ImGui.BeginChild(ctx, "Col1", 200, 0)
                        ImGui.TextColored(ctx, C_TEXT_SECONDARY, "ROOT NOTE")
                        ImGui.BeginGroup(ctx)
                        local btn_w = 44
                        for i, root in ipairs(roots) do
                            if i > 1 and (i-1) % 4 ~= 0 then ImGui.SameLine(ctx) end
                            if ToggleButton(root, selected_root_idx == i, btn_w) then
                                selected_root_idx = i
                            end
                        end
                        ImGui.EndGroup(ctx)
                        
                        ImGui.Dummy(ctx, 0, 16)
                        ImGui.TextColored(ctx, C_TEXT_SECONDARY, "OCTAVE")
                        ImGui.SetNextItemWidth(ctx, 180)
                        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, C_BG_SURFACE)
                        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, C_BG_SURFACE)
                        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, C_BG_SURFACE)
                        ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab, C_UI_TEAL)
                        ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive, C_UI_TEAL_ACTIVE)
                        local rv, new_oct = ImGui.SliderInt(ctx, "##Octave", selected_octave, 1, 5, "Oct %d")
                        if rv then selected_octave = new_oct end
                        ImGui.PopStyleColor(ctx, 5)
                    ImGui.EndChild(ctx)
                    
                    ImGui.SameLine(ctx, 0, 20)
                    
                    -- COLUMN 2: QUALITIES
                    ImGui.BeginChild(ctx, "Col2", 300, 0)
                        local quality_flat_index = 1
                        local q_btn_w = 66
                        for _, group in ipairs(chord_groups) do
                            ImGui.TextColored(ctx, C_TEXT_SECONDARY, string.upper(group.name))
                            for i, q in ipairs(group.chords) do
                                if i > 1 and (i-1) % 4 ~= 0 then ImGui.SameLine(ctx) end
                                if ToggleButton(q.name, selected_quality_idx == quality_flat_index, q_btn_w) then
                                    selected_quality_idx = quality_flat_index
                                end
                                quality_flat_index = quality_flat_index + 1
                            end
                            ImGui.Dummy(ctx, 0, 8)
                        end
                    ImGui.EndChild(ctx)
                    
                    ImGui.SameLine(ctx, 0, 20)
                    
                    -- COLUMN 3: PREVIEW & INSERT
                    ImGui.BeginChild(ctx, "Col3", 0, 0)
                        ImGui.Dummy(ctx, 0, 20)
                        local prev_root = roots[selected_root_idx]
                        local prev_qual = all_qualities[selected_quality_idx].short
                        local preview_str = prev_root .. prev_qual
                        
                        ImGui.TextColored(ctx, C_TEXT_SECONDARY, "READY TO INSERT:")
                        ImGui.PushFont(ctx, font_h2)
                        ImGui.TextColored(ctx, C_TEXT_PRIMARY, preview_str)
                        ImGui.PopFont(ctx)
                        
                        ImGui.Dummy(ctx, 0, 20)
                        
                        ImGui.PushStyleColor(ctx, ImGui.Col_Button, C_CTA_BRICK)
                        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C_CTA_HOVER) 
                        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C_CTA_ACTIVE)
                        ImGui.PushStyleColor(ctx, ImGui.Col_Text, C_TEXT_PRIMARY)
                        ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 0)
                        
                        if ImGui.Button(ctx, "INSERT CHORD", -1, 60) then InsertChord() end
                        
                        ImGui.PopStyleVar(ctx, 1)
                        ImGui.PopStyleColor(ctx, 4)
                    ImGui.EndChild(ctx)
                    
                    ImGui.EndTabItem(ctx)
                end
                
                -- ==========================================
                -- DISPLAY TAB
                -- ==========================================
                if ImGui.BeginTabItem(ctx, "Display") then
                    local current_chord, next_chord, progress = GetCurrentAndNextChords()
                    
                    ImGui.Dummy(ctx, 0, 20)
                    
                    ImGui.BeginChild(ctx, "DispTop", 0, 160)
                        -- COLUMN 1: CURRENT CHORD (60%)
                        ImGui.BeginChild(ctx, "DispCol1", (window_w - 200) * 0.55, 0)
                            local c_chord_str = current_chord or "---"
                            c_chord_str = c_chord_str:gsub(" Major", "")
                            ImGui.PushFont(ctx, font_h1)
                            local cc_w, _ = ImGui.CalcTextSize(ctx, c_chord_str)
                            ImGui.SetCursorPosX(ctx, (ImGui.GetWindowWidth(ctx) - cc_w) / 2)
                            ImGui.SetCursorPosY(ctx, 40)
                            ImGui.TextColored(ctx, C_TEXT_PRIMARY, c_chord_str)
                            ImGui.PopFont(ctx)
                        ImGui.EndChild(ctx)
                        
                        ImGui.SameLine(ctx, 0, 30)
                        
                        -- COLUMN 2: NEXT CHORD (40%)
                        ImGui.BeginChild(ctx, "DispCol2", 0, 0)
                            ImGui.Dummy(ctx, 0, 40)
                            local n_chord_val = next_chord or "---"
                            n_chord_val = n_chord_val:gsub(" Major", "")
                            local n_chord_str = "NEXT: " .. n_chord_val
                            ImGui.PushFont(ctx, font_h2)
                            ImGui.TextColored(ctx, C_TEXT_SECONDARY, n_chord_str)
                            ImGui.PopFont(ctx)
                        ImGui.EndChild(ctx)
                    ImGui.EndChild(ctx)
                    
                    ImGui.Dummy(ctx, 0, 10)
                    
                    -- Progress Bar (FULL WIDTH)
                    ImGui.PushStyleColor(ctx, ImGui.Col_PlotHistogram, C_CTA_BRICK)
                    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, C_BG_SURFACE)
                    ImGui.ProgressBar(ctx, progress, -1, 16, "")
                    ImGui.PopStyleColor(ctx, 2)
                    
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

r.defer(loop)
