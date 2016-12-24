require 'filesystem'
require 'sys'
require 'utility'
local nk = require 'nuklear'
local srv = require 'gui.backend'
local lni = require 'lni-c'
local showconsole = srv.debug
local currenttheme = {0, 173, 217}

NK_WIDGET_STATE_MODIFIED = 1 << 1
NK_WIDGET_STATE_INACTIVE = 1 << 2
NK_WIDGET_STATE_ENTERED  = 1 << 3
NK_WIDGET_STATE_HOVER    = 1 << 4
NK_WIDGET_STATE_ACTIVED  = 1 << 5
NK_WIDGET_STATE_LEFT     = 1 << 6

NK_TEXT_ALIGN_LEFT     = 0x01
NK_TEXT_ALIGN_CENTERED = 0x02
NK_TEXT_ALIGN_RIGHT    = 0x04
NK_TEXT_ALIGN_TOP      = 0x08
NK_TEXT_ALIGN_MIDDLE   = 0x10
NK_TEXT_ALIGN_BOTTOM   = 0x20
NK_TEXT_LEFT           = NK_TEXT_ALIGN_MIDDLE | NK_TEXT_ALIGN_LEFT
NK_TEXT_CENTERED       = NK_TEXT_ALIGN_MIDDLE | NK_TEXT_ALIGN_CENTERED
NK_TEXT_RIGHT          = NK_TEXT_ALIGN_MIDDLE | NK_TEXT_ALIGN_RIGHT

local root = fs.get(fs.DIR_EXE):remove_filename()
local config = lni(io.load(root / 'config.ini'))
local fmt = nil

local config_content = [[
-- 是否分析slk文件
read_slk = $read_slk$
-- 分析slk时寻找id最优解的次数,0表示无限,寻找次数越多速度越慢
find_id_times = $find_id_times$
-- 移除与模板完全相同的数据
remove_same = $remove_same$
-- 移除超出等级的数据
remove_exceeds_level = $remove_exceeds_level$
-- 移除只在WE使用的文件
remove_we_only = $remove_we_only$
-- 移除没有引用的对象
remove_unuse_object = $remove_unuse_object$
-- 转换为地图还是目录(map, dir)
target_storage = $target_storage$
]]

local function build_config(cfg)
	return config_content:gsub('%$(.-)%$', function(str)
		local value = cfg
		for key in str:gmatch '[^%.]*' do
			value = value[key]
		end
		return tostring(value)
	end)
end

local function save_config()
	local newline = [[

]]
	local str = {}
	str[#str+1] = ([[
[root]
-- 转换后的目标格式(lni, obj, slk)
target_format = %s
]]):format(config.target_format)

	for _, type in ipairs {'slk', 'lni', 'obj'} do
		str[#str+1] = ('[%s]'):format(type)
		str[#str+1] = build_config(config[type])
	end
	io.save(root / 'config.ini', table.concat(str, newline))
end

local window = nk.window('W3x2Lni', 400, 600)
window:set_theme(0, 173, 217)

local uitype = 'none'
local showmappath = false
local showcount = 0
local mapname = ''
local mappath = fs.path()

function window:dropfile(file)
	mappath = fs.path(file)
	mapname = mappath:filename():string()
	uitype = 'select'
end

local function set_current_theme(theme)
	if theme then
		currenttheme = theme
	end
	window:set_theme(table.unpack(currenttheme))
end

local function button_mapname(canvas, height)
	canvas:layout_row_dynamic(10, 1)
	canvas:layout_row_dynamic(40, 1)
	local ok, state = canvas:button(mapname)
	if ok then 
		showmappath = not showmappath
	end
	if state & NK_WIDGET_STATE_LEFT ~= 0 then
		showcount = showcount + 1
	else
		showcount = 0
	end
	if showmappath or showcount > 20 then
		canvas:edit(mappath:string(), 200, function ()
			return false
		end)
		height = height - 44
	end
	return height
end

local function button_about(canvas)
	canvas:layout_row_dynamic(20, 2)
	window:set_theme(51, 55, 67)
	canvas:text('', NK_TEXT_RIGHT)
	if canvas:button('版本: 1.0.0') then
		uitype = 'about'
	end
	set_current_theme()
end

local function window_about(canvas)
	canvas:layout_row_dynamic(20, 1)
	canvas:button_rect('作者', {-10, 0, 300, 30})
	canvas:layout_row_dynamic(5, 1)
	canvas:layout_row_dynamic(20, 4)
	canvas:text('前端: ', NK_TEXT_RIGHT) canvas:text('actboy168', NK_TEXT_CENTERED) 
	canvas:layout_row_dynamic(20, 4)
	canvas:text('后端: ', NK_TEXT_RIGHT) canvas:text('最萌小汐', NK_TEXT_CENTERED)
	canvas:layout_row_dynamic(5, 1)
	canvas:button_rect('说明', {-10, 0, 300, 30})
	canvas:layout_row_dynamic(375, 1)
	canvas:group('说明', function()
		canvas:layout_row_dynamic(25, 1)
		canvas:layout_row_dynamic(50, 4)
		canvas:text('', NK_TEXT_RIGHT)
		canvas:text('圣诞快乐！', NK_TEXT_CENTERED)
	end)
	canvas:layout_row_dynamic(30, 1)
	if canvas:button('返回') then
		if mapname == '' then
			uitype = 'none'
		else
			uitype = 'select'
		end
	end
end

local function window_none(canvas)
	canvas:layout_row_dynamic(2, 1)
	canvas:layout_row_dynamic(200, 1)
	canvas:button('把地图拖进来')
	canvas:layout_row_dynamic(320, 1)
	button_about(canvas)
end

local function clean_convert_ui()
	srv.message = ''
	srv.progress = nil
	srv.report = {}
end

local function window_select(canvas)
	canvas:layout_row_dynamic(2, 1)
	canvas:layout_row_dynamic(100, 1)
	window:set_theme(0, 173, 217)
	if canvas:button('转为Lni') then
		uitype = 'convert'
		fmt = 'lni'
		window:set_title('W3x2Lni')
		config.target_format = 'lni'
		config.lni.target_storage = 'dir'
		config.lni.read_slk = false
		config.lni.remove_same = false
		config.lni.remove_exceeds_level = false
		config.lni.remove_we_only = false
		config.lni.remove_unuse_object = false
		save_config()
		clean_convert_ui()
		set_current_theme {0, 173, 217}
		return
	end
	window:set_theme(0, 173, 60)
	if canvas:button('转为Slk') then
		uitype = 'convert'
		fmt = 'slk'
		window:set_title('W3x2Slk')
		config.target_format = 'slk'
		config.slk.target_storage = 'map'
		config.slk.read_slk = true
		config.slk.remove_same = true
		config.slk.remove_exceeds_level = true
		save_config()
		clean_convert_ui()
		set_current_theme {0, 173, 60}
		return
	end
	window:set_theme(217, 163, 60)
	if canvas:button('转为Obj') then
		uitype = 'convert'
		fmt = 'obj'
		window:set_title('W3x2Obj')
		config.target_format = 'obj'
		config.obj.target_storage = 'map'
		config.obj.read_slk = false
		config.obj.remove_same = true
		config.obj.remove_exceeds_level = false
		config.obj.remove_we_only = false
		config.obj.remove_unuse_object = false
		save_config()
		clean_convert_ui()
		set_current_theme {217, 163, 60}
		return
	end
	canvas:layout_row_dynamic(212, 1)
	button_about(canvas)
end

local backend

local function update_backend()
	if showconsole then
		showconsole = false
		nk:console()
	end
	if not backend then
		return
	end
	if backend:update() then
		backend = nil
	end
end
	
local function window_convert(canvas)
	local height = button_mapname(canvas, 290)
	canvas:layout_row_dynamic(10, 1)
	if fmt == 'lni' or fmt == 'obj' then
		height = height - 34
		canvas:layout_row_dynamic(30, 1)
		if canvas:checkbox('读取slk文件', config[fmt].read_slk) then
			config[fmt].read_slk = not config[fmt].read_slk
			save_config()
		end
	else
		height = height - 60
		canvas:layout_row_dynamic(30, 1)
		if canvas:checkbox('简化', config[fmt].remove_unuse_object) then
			config[fmt].remove_unuse_object = not config[fmt].remove_unuse_object
			save_config()
		end
		canvas:layout_row_dynamic(30, 1)
		if canvas:checkbox('删除只在WE中使用的文件', config[fmt].remove_we_only) then
			config[fmt].remove_we_only = not config[fmt].remove_we_only
			save_config()
		end
	end
	canvas:layout_row_dynamic(10, 1)
	canvas:tree('高级', 1, function()
		canvas:layout_row_dynamic(30, 1)
		if canvas:checkbox('限制搜索最优模板的次数', config[fmt].find_id_times ~= 0) then
			if config[fmt].find_id_times == 0 then
				config[fmt].find_id_times = 10
			else
				config[fmt].find_id_times = 0
			end
			save_config()
		end
		if config[fmt].find_id_times == 0 then
			canvas:edit('', 0, function ()
				return false
			end)
		else
			local r = canvas:edit(tostring(config[fmt].find_id_times), 10, function (c)
				return 48 <= c and c <= 57
			end)
			config[fmt].find_id_times = tonumber(r) or 1
			save_config()
		end
		height = height - 68
	end)

	canvas:layout_row_dynamic(height, 1)
	canvas:layout_row_dynamic(30, 1)
	canvas:text(srv.message, NK_TEXT_LEFT)
	canvas:layout_row_dynamic(10, 1)
	canvas:layout_row_dynamic(30, 1)
	if backend or #srv.report == 0 then
		canvas:progress(math.floor(srv.progress or 0), 100)
	else
		if canvas:button('详情') then
			uitype = 'report'
		end
	end
	canvas:layout_row_dynamic(10, 1)
	canvas:layout_row_dynamic(50, 1)
	if backend then
		canvas:button('正在处理...')
	else
		if canvas:button('开始') then
			canvas:progress(0, 100)
			backend = srv.async_popen(('"%s" -backend "%s"'):format(fs.get(fs.DIR_EXE):string(), mappath:string()))
			srv.message = '正在初始化...'
			srv.progress = nil
			srv.report = {}
		end
	end
end

local function window_report(canvas)
	canvas:layout_row_dynamic(500, 1)
	canvas:group('详情', function()
		canvas:layout_row_dynamic(25, 1)
		for _, s in ipairs(srv.report) do
			if s[1] == 'error' then
				window:set_style('text.color', 190, 30, 30)
				canvas:text(s[2], NK_TEXT_LEFT, s[3])
				window:set_style('text.color', 190, 190, 190)
			else
				canvas:text(s[2], NK_TEXT_LEFT, s[3])
			end
		end
	end)
	canvas:layout_row_dynamic(20, 1)
	canvas:layout_row_dynamic(30, 1)
	if canvas:button('返回') then
		uitype = 'convert'
	end
end

local dot = 0
function window:draw(canvas)
	update_backend()
	if uitype == 'none' then
		window_none(canvas)
		return
	end
	if uitype == 'about' then
		window_about(canvas)
		return
	end
	if uitype == 'select' then
		window_select(canvas)
		return
	end
	if uitype == 'report' then
		window_report(canvas)
		return
	end
	window_convert(canvas)
end

window:run()
