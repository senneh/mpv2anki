local util = require('mp.utils')
local msg = require('mp.msg')
local mpopt = require('mp.options')

-- either modify your options here or create a config file in ~/.config/mpv/script-opts/mpv2anki.conf 
local options = {
    -- absolute path to where anki saves its media on linux this is usually the form of
    -- '/home/$user/.local/share/Anki2/$ankiprofile/collection.media/'
	-- relative paths (e.g. ~ for home dir) do NOT work.
    media_path = '',
    -- The anki deck where to put the cards
    deckname = 'mpv2anki',
    -- The note type
    modelName = 'mpv2anki',
    -- You can use these options to remap the fields
    field_audio = 'audio',
    field_snapshot = 'snapshot',
    field_subtitle1 = 'subtitle1',
    field_subtitle2 = 'subtitle2',
    field_start_time = 'start_time',
    field_end_time = 'end_time',
    field_snapshot_time = 'snapshot_time',
	field_title = 'title',
    -- The font size used in the menu.
    font_size = 20,
    shortcut = 'shift+f',
    -- In case you changed it
    anki_url = 'localhost:8765',
    audio_bitrate = '128k',
    snapshot_height = '480',
}

mpopt.read_options(options)

local overlay = mp.create_osd_overlay('ass-events')

local ctx = {
    start_time = -1,
    end_time = -1,
    snapshot_time = -1,
    sub = {'',''},
}

------------------------------------------------------------
-- utility functions

local function time_to_string(seconds)
    if seconds < 0 then
        return 'empty'
    end
    local time = string.format('.%03d', seconds * 1000 % 1000);
    time = string.format('%02d:%02d%s',
        seconds / 60 % 60,
        seconds % 60,
        time)

    if seconds > 3600 then
        time = string.format('%02d:%s', seconds / 3600, time)
    end

    return time
end

local function time_to_string2(seconds)
    return string.format('%02dh%02dM%02ds%03dm',
        seconds / 3600,
        seconds / 60 % 60,
        seconds % 60,
        seconds * 1000 % 1000)
end

------------------------------------------------------------
-- anki functions

-- All anki requests are of the form:
-- {
--  "action" : @action
--  "version" : 6
--  "params" : @t_params (optional)
-- }
-- and return a lua table with 2 keys, "result" and "error"
local function anki_connect(action, t_params, url)
    local url = url or 'localhost:8765'

    local request = {
        action = action,
        version = 6,
    }

    if t_params ~= nil then
        request.params = t_params
    end

    local json = util.format_json(request)

    local command = {
        'curl', url, '-X', 'POST', '-d', json
    }

    local result = mp.command_native({
        name = 'subprocess',
        args = command,
        capture_stdout = true,
        capture_stderr = true,
    })

    result = util.parse_json(result.stdout)

    return result.result, result.error
end

------------------------------------------------------------
-- creating media and anki note

function generate_media_name()
    local name = mp.get_property('filename/no-ext')
    name = string.gsub(name, '[%[%]]', '')
    return 'mpv2anki_' .. name
end

-- Creates an audio fragment with @start_time and @end_time in @media_path.
-- Returns a string containing the name to the audio file
-- or an empty string on error
function create_audio(
    media_path,
    filename_prefix,
    start_time,
    end_time,
    bitrate)

    if (start_time < 0 or end_time < 0) or
       (start_time == end_time) then
        return ''
    end

    if start_time > end_time then
        local t = start_time
        start_time = end_time
        end_time = t
    end

    local filename = string.format(
        '%s_(%s-%s).mp3',
        filename_prefix,
        time_to_string2(start_time),
        time_to_string2(end_time))

    local encode_args = {
        'mpv', mp.get_property('path'),
        '--start=' .. start_time,
        '--end=' .. end_time,
        '--aid=' .. mp.get_property("aid"),
        '--vid=no',
        '--loop-file=no',
        '--oacopts=b=' .. bitrate,
        '-o=' .. media_path .. filename
    }

    local result = mp.command_native({
        name = 'subprocess',
        args = encode_args,
        capture_stdout = true,
        capture_stderr = true,
    })

    return filename
end

-- Takes a snapshot at @snapshot_time and writes it to @media_path
-- Returns a string containing the name to the snapshot
-- or an empty string on error
function create_snapshot(media_path, filename_prefix, snapshot_time, height)
    if (snapshot_time <= 0) then
        return ''
    end

    local filename = string.format(
        '%s_(%s).jpg',
        filename_prefix,
        time_to_string2(snapshot_time)
    )

    -- Sadly the screenshot command does not allow us to create screenshots on specific
    -- times nor resize images. So we have to encode to a single image instead
    local encode_args = {
        'mpv', mp.get_property('path'),
        '-start=' .. snapshot_time,
        '--frames=1',
        '--no-audio',
        '--no-sub',
        '--vf-add=scale=-2:' .. height,
        -- See https://github.com/mpv-player/mpv/issues/6088
        -- This is the equivalent of --ovcopts=qscale=2
        '--ovcopts=global_quality=2*QP2LAMBDA,flags=+qscale',
        '--loop-file=no',
        '-o=' .. media_path .. filename
    }

    local result = mp.command_native({
        name = 'subprocess',
        args = encode_args,
        capture_stdout = true,
        capture_stderr = true,
    })

    return filename
end

function create_anki_note(gui)

    local filename_prefix = generate_media_name()

    local filename_audio = create_audio(
        options.media_path,
        filename_prefix,
        ctx.start_time,
        ctx.end_time,
        options.audio_bitrate)

    local filename_snapshot = create_snapshot(
        options.media_path,
        filename_prefix,
        ctx.snapshot_time,
        options.snapshot_height
    )

    -- Start filling the fields
    local fields = {}

    if #filename_audio > 0 then
        fields[options.field_audio] = '[sound:'..filename_audio..']'
        fields[options.field_start_time] = time_to_string(ctx.start_time)
        fields[options.field_end_time] = time_to_string(ctx.end_time)
    end

    if #filename_snapshot > 0 then
        fields[options.field_snapshot] = '<img src="' .. filename_snapshot ..'">'
        fields[options.field_snapshot_time] = time_to_string(ctx.snapshot_time)
    end

    if #ctx.sub[1] > 0 then
        fields[options.field_subtitle1] = ctx.sub[1]
    end

    if #ctx.sub[2] > 0 then
        fields[options.field_subtitle2] = ctx.sub[2]
    end

	fields[options.field_title] = mp.get_property('filename/no-ext')

	local param = {
        note = {
            deckName = options.deckname,
            modelName = options.modelName,
            fields = fields,
            tags = {
                'mpv2anki'
            }
        }
    }

    local action;

    if gui then
        action = 'guiAddCards'
    else
        action = 'addNote'
    end

    anki_connect(action, param, options.anki_url)
end

------------------------------------------------------------
-- main menu

local menu_keybinds = {
    { key = '1', fn = function() menu_set_time('start_time', 'time-pos') end },
    { key = '2', fn = function() menu_set_time('end_time', 'time-pos') end },
    { key = '3', fn = function() menu_set_time('snapshot_time', 'time-pos') end },
    { key = '4', fn = function() menu_set_subs(1) end },
    { key = '5', fn = function() menu_set_subs(2) end },
    { key = 'd', fn = function() menu_set_to_subs() end },
    { key = 'D', fn = function() menu_clear_all() end },
    { key = 'S', fn = function() menu_set_time('end_time', 'sub-end') end },
    { key = 's', fn = function() menu_set_time('start_time', 'sub-start') end },
    { key = 'a', fn = function() menu_append(1) end },
    { key = 'A', fn = function() menu_append(2) end },
    { key = 'e', fn = function() create_anki_note(true) end },
    { key = 'shift+e', fn = function() create_anki_note(false) end },
    { key = 'ESC', fn = function() menu_close() end },
}

function menu_append(n)
    local subs = mp.get_property('sub-text'):gsub('\n', '')

    ctx.sub[n] = ctx.sub[n] .. ' ' .. subs

    menu_update()
end

function menu_set_to_subs()
	local start_time = mp.get_property_number('sub-start')
	local end_time = mp.get_property_number('sub-end')
	
	if start_time == nil then
		start_time = -1
	end
	
	if end_time == nil then
		end_time = -1
	end
	
	ctx.start_time =  start_time
	ctx.end_time = end_time
	ctx.sub[1] = mp.get_property('sub-text'):gsub('\n', '')
	
	menu_update()
end

function menu_set_time(field, prop)
    local time = mp.get_property_number(prop)

    if time == nil or time == ctx[field] then
        ctx[field] = -1
    else
        ctx[field] = time
    end

    menu_update()
end

function menu_set_subs(n)
    local subs = mp.get_property('sub-text'):gsub('\n', '')

    if subs == ctx.sub[n] then
        ctx.sub[n] = ''
    else
        ctx.sub[n] = subs
    end
    menu_update()
end

function menu_clear_all()
	ctx.start_time = -1
	ctx.end_time = -1
	ctx.snapshot_time = -1
	ctx.sub[1] = ''
	ctx.sub[2] = ''
	
	menu_update()
end


function menu_update()
    local ass = ASS.new():s(options.font_size):b('MPV2Anki'):nl():nl()

    -- Media type
    ass:b('Audio fragment'):nl()

    ass:tab():b('1: ')
        :a('Set start time (' .. time_to_string(ctx.start_time) .. ')'):nl()
    ass:tab():b('2: ')
        :a('Set end time (' .. time_to_string(ctx.end_time) .. ')'):nl()
        :nl()

    -- snapshot
    ass:b('Snapshot'):nl()

    ass:tab():b('3: ')
        :a('Set snapshot (' .. time_to_string(ctx.snapshot_time) .. ')'):nl()
        :nl()

    -- subtitle
    ass:b('Subtitles'):nl()
    local start_key = 4
    for i, sub in pairs(ctx.sub) do
        ass:tab():b(start_key .. ': ')
            :a('sub ' .. i)
        if sub == '' then sub = 'empty' end
        ass:a(' (' .. sub .. ')'):nl()
        start_key = start_key + 1
    end

    -- menu options
    ass:nl()
		:b('d: '):a('Set to current subtitle ('):b('D: '):a('clear all)'):nl()
		:b('s: '):a('Set end time to sub ('):b('S: '):a('begin time)'):nl()
	    :b('a: '):a('Append sub 1 ('):b('A: '):a('sub 2)'):nl()
		:b('e: '):a('Create card ('):b('E: '):a('without GUI)'):nl()
        :b('ESC: '):a('Close'):nl()

    ass:draw()
end

function menu_close()
    for _, val in pairs(menu_keybinds) do
        mp.remove_key_binding(val.key)
    end
    overlay:remove()
end


function menu_open()
    for _, val in pairs(menu_keybinds) do
        mp.add_key_binding(val.key, val.key, val.fn)
    end
    menu_update()
end

------------------------------------------------------------
-- Helper functions for styling ASS messages

ASS = {}
ASS.__index = ASS

function ASS.new()
    return setmetatable({text=''}, ASS)
end

-- append
function ASS:a(s)
    self.text = self.text .. s
    return self
end

-- bold
function ASS:b(s)
    return self:a('{\\b1}' .. s .. '{\\b0}')
end

-- new line
function ASS:nl()
    return self:a('\\N')
end

-- 4 space tab
function ASS:tab()
    return self:a('\\h\\h\\h\\h')
end

-- size
function ASS:s(size)
    return self:a('{\\fs' .. size .. '}')
end

function ASS:draw()
    overlay.data = self.text
    overlay:update()
end

------------------------------------------------------------
-- Finally, set an 'entry point' in mpv

mp.add_key_binding(options.shortcut, options.shortcut, menu_open)
