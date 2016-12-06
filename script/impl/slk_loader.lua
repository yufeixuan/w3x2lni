local key_type = require 'key_type'
local lni = require 'lni'

local table_insert = table.insert
local table_unpack = table.unpack
local type = type
local tonumber = tonumber
local pairs = pairs
local ipairs = ipairs

-- 规则如下
-- 1.如果第一个字符是逗号,则添加一个空串
-- 2.如果最后一个字符是逗号,则添加一个空标记
-- 3.如果最后一个字符是引号,则忽略该字符
-- 4.如果当前字符为引号,则匹配到下一个引号,并忽略2端的字符
-- 5.如果当前字符为逗号,则忽略该字符.如果上一个字符是逗号,则添加一个空串
-- 6.否则匹配到下一个逗号,并忽略该字符
local function splite(str)
    local tbl = {}
    local cur = 1
    if str:sub(1, 1) == ',' then
        tbl[#tbl+1] = ''
    end
    while cur <= #str do
        if str:sub(cur, cur) == '"' then
            if cur == #str then
                break
            end
            local pos = str:find('"', cur+1, true) or (#str+1)
            tbl[#tbl+1] = str:sub(cur+1, pos-1)
            cur = pos+1
        elseif str:sub(cur, cur) == ',' then
            if str:sub(cur-1, cur-1) == ',' then
                tbl[#tbl+1] = ''
            end
            cur = cur+1
        else
            local pos = str:find(',', cur+1, true) or (#str+1)
            tbl[#tbl+1] = str:sub(cur, pos-1)
            cur = pos+1
        end
    end
    if str:sub(-1, -1) == ',' then
        tbl[#tbl+1] = false
    end
    return tbl
end


local mt = {}
mt.__index = mt

function mt:add_slk(slk)
    table_insert(self.slk, slk)
end

function mt:add_txt(txt)
    table_insert(self.txt, txt)
end

function mt:key2id(name, code, key)
    local key = key:lower()
    local id = code and self.key[code] and self.key[code][key] or self.key[name] and self.key[name][key] or self.key['public'][key]
    if id then
        return id
    end
    return nil
end

function mt:read_slk(lni, slk)
    for name, data in pairs(slk) do
        lni[name] = self:read_slk_obj(name, data)
    end
end

function mt:read_slk_obj(name, data)
    local obj = {}
    obj._user_id = name
    obj._origin_id = data.code
    obj._name = data.name  -- 单位的反slk可以用name作为线索
    obj._slk = true

    for key, value in pairs(data) do
        self:read_slk_data(name, obj, key, value)
    end

    return obj
end

function mt:read_slk_data(name, obj, key, value)
    local level = tonumber(key:sub(-1))
    if level then
        key = key:sub(1, -2)
    end
    local id = self:key2id(name, obj.code, key)
    if not id then
        return nil
    end

    self:add_data(obj, key, id, value, level)
    return true
end

function mt:read_txt(lni, txt)
    for name, data in pairs(txt) do
        self:read_txt_obj(lni[name], name, data)
    end
end

function mt:read_txt_obj(obj, skill, data)
    if obj == nil then
        return
    end

    obj['_txt'] = true

    for key, value in pairs(data) do
        self:read_txt_data(name, obj, key, value, data)
    end
end

function mt:read_txt_data(name, obj, key, value, txt)
    local data = {}
    local id = self:key2id(name, obj.code, key)
    local tbl = splite(value)

    if id == nil then
        if txt == nil then
            return
        end
        for i = 1, #tbl do
            local new_key = key .. ':' .. i
            self:read_txt_data(name, obj, new_key, tbl[i])
        end
        return
    end
    
    local meta = self.meta[id]
    if meta['appendIndex'] == 1 and txt then
        local max_level = txt[key..'count'] or 1
        for i = 1, max_level do
            local new_key
            if i == 1 then
                new_key = key
            else
                new_key = key .. (i-1)
            end
            self:read_txt_data(name, obj, key, txt[new_key])
        end
    end

    local max_level = #tbl
    if meta['index'] == -1 then
        if tbl[#tbl] == false then
            tbl[#tbl] = nil
        end
        tbl[1] = table.concat(tbl, ',')
        max_level = 1
    end
    if not meta['repeat'] or meta['repeat'] == 0 then
        max_level = 1
    end

    for i = 1, max_level do
        self:add_data(obj, key, id, tbl[i])
    end
end

function mt:add_data(obj, key, id, value, level)
    if obj[key] == nil then
        obj[key] = {
            ['_key'] = key,
            ['_id']  = id,
        }
    end
    if level == nil then
        level = #obj[key] + 1
    end
    obj[key][level] = value
end

function mt:get_key_type(id)
    local meta = self.meta
    local type = meta[id]['type']
    local format = key_type[type] or 3
    return format
end

function mt:to_type(id, value)
    local tp = self:get_key_type(id)
    if tp == 0 then
        value = math.floor(tonumber(value) or 0)
    elseif tp == 1 or tp == 2 then
        value = (tonumber(value) or 0.0) + 0.0
    elseif tp == 3 then
        if type(value) == 'string' then
            if value:match '^%s*[%-%_]%s*$' then
                value = nil
            end
        end
    end
    return value
end

function mt:set_default_value(lni)
    for _, obj in pairs(lni) do
        for key, data in pairs(obj) do
            if key:sub(1, 1) ~= '_' then
                for i, value in pairs(data) do
                    if type(i) == 'number' then
                        data[i] = self:to_type(data._id, value)
                    end
                end
            end
        end
    end
end

function mt:save()
    local data = {}

    -- 默认数据
    for _, slk in ipairs(self.slk) do
        self:read_slk(data, slk)
    end
    for _, txt in ipairs(self.txt) do
        self:read_txt(data, txt)
    end

    self:set_default_value(data)

    return data
end

return function (w2l, file_name, loader)
    local self = setmetatable({}, mt)

    self.slk = {}
    self.txt = {}

    local slk = w2l.info['template']['slk'][file_name]
    for i = 1, #slk do
        self:add_slk(w2l:read_slk(loader(w2l.dir['meta'] / slk[i])))
    end

    local txt = w2l.info['template']['txt'][file_name]
    for i = 1, #txt do
        self:add_txt(w2l:read_txt(loader(w2l.dir['meta'] / txt[i])))
    end

    self.meta = w2l:read_metadata(w2l.dir['meta'] / w2l.info['metadata'][file_name])
    self.key = lni:loader(loader(w2l.dir['key'] / (file_name .. '.ini')), file_name)

    return self:save()
end