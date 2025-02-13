local speclist_on = true

do
    local table_concat = table.concat
    local debug_getregistry = debug.getregistry
    local pcall = pcall
    local error = error
    local load = load
    local select = select
    local type = type
    local unpack = unpack
    local debug_getinfo = debug.getinfo
    local ipairs = ipairs
    local pairs = pairs

    ---
    local file_read = file.Read

    ---
    local LUA_LDIR = "!\\lua\\"
    local LUA_PATH_DEFAULT = table_concat {".\\?.lua;", LUA_LDIR, "?.lua;", LUA_LDIR, "?\\init.lua;"}
    local LUA_DIRSEP = "\\"
    local LUA_PATHSEP = ";"
    local LUA_PATH_MARK = "?"
    local LUA_EXECDIR = "!"
    local LUA_IGMARK = "-"
    local LUA_PATH_CONFIG = table_concat({LUA_DIRSEP, LUA_PATHSEP, LUA_PATH_MARK, LUA_EXECDIR, LUA_IGMARK, ""}, "\n")

    local LUA_LOADLIBNAME = "package"
    local LUA_REGISTRYINDEX = debug_getregistry()

    ---
    local function setprogdir(path)
        return path:gsub(LUA_EXECDIR, ".")
    end

    local function readable(filename)
        return pcall(file_read, filename:gsub("^%.\\", ""))
    end

    local function loadfile(filename, mode, env)
        local success, result = readable(filename)
        if not success then return error(("cannot open %s: %s"):format(filename, result:lower())) end
        return load(result, ("=%s"):format(filename), mode, env)
    end

    local function getfuncname()
        return debug_getinfo(2, "n").name or "?"
    end

    local function package_searchpath(...)
        local args = {...}
        local name, path, sep, rep = unpack(args)
        if select("#", ...) < 3 then sep, rep = ".", LUA_DIRSEP end
        if select("#", ...) < 4 then rep = LUA_DIRSEP end
        local funcname = getfuncname()
        if type(name) ~= "string" then return error(("bad argument #1 to '%s' (string expected, got %s)"):format(funcname, select("#", ...) < 1 and "no value" or type(name))) end
        if type(path) ~= "string" then return error(("bad argument #2 to '%s' (string expected, got %s)"):format(funcname, select("#", ...) < 2 and "no value" or type(path))) end
        if type(sep) ~= "string" then return error(("bad argument #3 to '%s' (string expected, got %s)"):format(funcname, select("#", ...) < 3 and "no value" or type(sep))) end
        if type(rep) ~= "string" then return error(("bad argument #4 to '%s' (string expected, got %s)"):format(funcname, select("#", ...) < 4 and "no value" or type(rep))) end

        local msg = {}
        if sep then name = name:gsub(("%%%s"):format(sep), ("%%%s"):format(rep)) end

        for current in path:gmatch(("[^%s]+"):format(LUA_PATHSEP)) do
            local filename = current:gsub(("%%%s"):format(LUA_PATH_MARK), name)
            if readable(filename) then return filename end
            msg[#msg + 1] = ("\n\tno file '%s'"):format(filename)
        end

        return nil, table_concat(msg)
    end

    local function package_loader_preload(...)
        local name = unpack {...}
        if type(name) ~= "string" then return error(("bad argument #1 to '%s' (string expected, got %s)"):format(getfuncname(), select("#", ...) < 1 and "no value" or type(name))) end

        local preload = _G[LUA_LOADLIBNAME]["preload"]
        if type(preload) ~= "table" then return error "'package.preload' must be a table" end

        if preload[name] ~= nil then return preload[name] end
        return ("\n\tno field package.preload['%s']"):format(name)
    end

    local function package_loader_lua(...)
        local args = {...}
        local name = unpack(args)
        if type(name) ~= "string" then return error(("bad argument #1 to '%s' (string expected, got %s)"):format(getfuncname(), select("#", ...) < 1 and "no value" or type(name))) end

        local path = _G[LUA_LOADLIBNAME]["path"]
        if type(path) ~= "string" then return error "'package.path' must be a string" end

        local filename, msg
        filename, msg = package_searchpath(name, path)
        if not filename then return msg end

        local chunk, err = loadfile(filename)
        if chunk then return chunk end
        return error(("error loading module '%s' from file '%s':\n\t%s"):format(name, filename, err))
    end

    local KEY_SENTINEL = bit.bor(bit.lshift(0x80000000, 32), 115)
    local function package_require(...)
        local name = unpack {...}

        if type(name) ~= "string" then return error(("bad argument #1 to '%s' (string expected, got %s)"):format(getfuncname(), select("#", ...) < 1 and "no value" or type(name))) end

        local package = _G[LUA_LOADLIBNAME]
        local loaders = package["loaders"]
        if type(loaders) ~= "table" then return error "'package.loaders' must be a table" end

        local loaded = package["loaded"]

        if loaded[name] then
            if loaded[name] == KEY_SENTINEL then return error(("loop or previous error loading module '%s'"):format(name)) end
            return loaded[name]
        end

        local msg = {}
        for _, loader in ipairs(loaders) do
            local success, result = pcall(loader, name)
            if not success then return error(result) end

            if type(result) == "function" then
                loaded[name] = KEY_SENTINEL
                local ok, res = pcall(result, name)

                if not ok then
                    loaded[name] = nil
                    return print(res)
                end

                loaded[name] = type(res) == "nil" and true or res
                return loaded[name]
            elseif type(result) == "string" then
                msg[#msg + 1] = result
            end
        end

        return error(("module '%s' not found:%s"):format(name, table_concat(msg)))
    end

    local function luaopen_package()
        _G[LUA_LOADLIBNAME] = {
            ["searchpath"] = package_searchpath,
            ["loaders"] = {
                package_loader_preload,
                package_loader_lua
            },
            ["path"] = setprogdir(LUA_PATH_DEFAULT),
            ["config"] = LUA_PATH_CONFIG,
            ["loaded"] = LUA_REGISTRYINDEX["_LOADED"],
            ["preload"] = LUA_REGISTRYINDEX["_PRELOAD"]
        }

        for name, func in pairs {
            ["require"] = package_require
        } do
            _G[name] = func
        end
    end

    if not package then luaopen_package() end
end

local ffi = require "ffi"
local table_new = require "table.new"

---@format disable-next
local vtable_bind, vtable_thunk = (function()local a=(function()local b=ffi.typeof"void***"return function(c,d,e)return ffi.cast(e,ffi.cast(b,c)[0][d])end end)()local function f(c,d,e,...)local g=a(c,d,ffi.typeof(e,...))return function(...)return g(c,...)end end;local function h(d,e,...)e=ffi.typeof(e,...)return function(c,...)return a(c,d,e)(c,...)end end;return f,h end)()

local function create_interface(module_name, interface_name)
    local address = mem.FindPattern(module_name, "4C 8B 0D ?? ?? ?? ?? 4C 8B D2 4C 8B D9")
    if not address then return nil end

    local result = ffi.cast("void*(__cdecl*)(const char*, int*)", address)(interface_name, nil)
    return result ~= nil and result or nil
end

local schema
do
    ffi.cdef([[
        typedef struct $ {
            void* vftable;
            const char* m_pszName;
            void* m_pTypeScope;
            uint8_t m_unTypeCategory;
            uint8_t m_unAtomicCategory;
        } $
    ]], "CSchemaType", "CSchemaType")
    assert(ffi.sizeof "CSchemaType" == 0x20)

    ffi.cdef([[
        typedef struct $ {
            const char* m_pszName;
            struct CSchemaType* m_pSchemaType;
            int32_t m_nSingleInheritanceOffset;
            int32_t m_nMetadataSize;
            void* m_pMetadata;
        } $
    ]], "SchemaClassFieldData_t", "SchemaClassFieldData_t")
    assert(ffi.sizeof "SchemaClassFieldData_t" == 0x20)

    ffi.cdef([[
        typedef struct $ {
            struct SchemaClassInfoData_t* m_pSelf;
            const char* m_pszName;
            const char* m_pszModule;
            int m_nSizeOf;
            int16_t m_nFieldSize;
            int16_t m_nStaticFieldsSize;
            int16_t m_nStaticMetadataSize;
            uint8_t m_unAlignOf;
            int8_t m_nBaseClassSize;
            int16_t m_nMultipleInheritanceDepth;
            int16_t m_nSingleInheritanceDepth;
            struct SchemaClassFieldData_t* m_pFields;
            void* m_pStaticFields;
            struct {
                unsigned int m_unOffset;
                struct SchemaClassInfoData_t* m_pClass;
            }* m_pBaseClasses;
            void* m_pFieldMetadataOverrides;
            void* m_pStaticMetadata;
            void* m_pTypeScope;
            struct CSchemaType* m_pSchemaType;
            uint8_t m_nClassFlags;
            uint32_t m_unSequence;
            void* m_pFn;
        } $
    ]], "SchemaClassInfoData_t", "SchemaClassInfoData_t")
    assert(ffi.offsetof("SchemaClassInfoData_t", "m_pFn") == 0x68)

    local CSchemaSystem = create_interface("schemasystem.dll", "SchemaSystem_001")
    local native_FindTypeScopeForModule = vtable_bind(CSchemaSystem, 13, "void*(__thiscall*)(void*, const char*, void*)")
    local native_FindDeclaredClass = vtable_thunk(25, "SchemaClassInfoData_t*(__thiscall*)(void*, const char*)")

    local function create_map(typescope, size)
        local map = table_new(0, size)
        local data = ffi.cast("uintptr_t*", ffi.cast("uintptr_t", typescope) + 0x0440)[0]
        for i = 0, size - 1 do
            local classname = ffi.string(ffi.cast("const char**", ffi.cast("uintptr_t*", ffi.cast("uint8_t*", data + i * 0x18) + 0x10)[0] + 0x8)[0])
            local declared = native_FindDeclaredClass(typescope, classname)

            if not map[classname] then map[classname] = table_new(0, declared.m_nFieldSize) end

            for j = 0, declared.m_nFieldSize - 1 do
                local field = declared.m_pFields[j]
                local propname = ffi.string(field.m_pszName)

                if not map[classname][propname] then map[classname][propname] = field.m_nSingleInheritanceOffset end
            end

            local inherit = {}
            local classes = declared.m_pBaseClasses
            while classes ~= nil do
                local cls = classes.m_pClass
                inherit[#inherit + 1] = ffi.string(cls.m_pszName)
                classes = cls.m_pBaseClasses
            end

            setmetatable(map[classname], {
                __index = function(_, key)
                    for _, parentclassname in ipairs(inherit) do
                        if map[parentclassname] and map[parentclassname][key] then return map[parentclassname][key] end
                    end
                end
            })
        end
        return map
    end

    schema = setmetatable({
        map = {}
    }, {
        __call = function(self, classname, propname)
            return self:find(classname, propname)
        end,
        __index = {
            find = function(self, classname, propname)
                for _, map in pairs(self.map) do
                    if map[classname] and map[classname][propname] then return map[classname][propname] end
                end
            end,
            open = function(self, modname)
                local typescope = native_FindTypeScopeForModule(modname, nil)
                if typescope == nil then error(string.format("invalid type range to find '%s'", modname), 2) end

                local size = ffi.cast("uint16_t*", ffi.cast("uintptr_t", typescope) + 0x0456)[0]
                self.map[modname] = create_map(typescope, size)
                return self
            end
        }
    }):open "client.dll"
end

local function schema_offsetof(ctype, classname, propname, array_index)
    local offset = schema:find(classname, propname)
    if not offset then return end

    if type(propname) == "table" then
        for _, prop in ipairs(propname) do
            offset = type(offset) == "table" and offset[prop]
            if not offset then return end
        end
    end

    local ct = ffi.typeof("$*", ffi.typeof(ctype))

    return function(...)
        local args = {...}
        local argc = select("#", ...)

        if argc == 1 then
            local p = ffi.cast(ct, ffi.cast("uintptr_t", args[1]) + offset)
            if array_index then return p[array_index] end
            return p
        end

        if argc == 2 then
            local p = ffi.cast(ct, ffi.cast("uintptr_t", args[1]) + offset)
            p[array_index] = args[2]
        end
    end
end

local function new_class(name)
    return function(def)
        if type(def) == "string" then
            ffi.cdef(string.format("typedef struct $ {%s} $", def), name, name)
            return function(meta) return ffi.metatype(name, meta) end
        end

        ffi.cdef("typedef struct $ {} $", name, name)
        return ffi.metatype(name, def)
    end
end

do
    local offsetof_t = {
        m_iObserverMode = schema_offsetof("uint8_t", "CPlayer_ObserverServices", "m_iObserverMode", 0),
        m_hObserverTarget = schema_offsetof("uintptr_t", "CPlayer_ObserverServices", "m_hObserverTarget", 0)
    }

    local M = {
    }

    new_class "CPlayer_ObserverServices" {
        __index = function(self, key)
            if M[key] then return M[key] end
            if offsetof_t[key] then return offsetof_t[key](self) end
        end,
        __newindex = function(self, key, value)
            if offsetof_t[key] then return offsetof_t[key](self, value) end
        end
    }
end

do
    local offsetof_t = {
        m_pObserverServices = schema_offsetof("CPlayer_ObserverServices*", "C_BasePlayerPawn", "m_pObserverServices", 0)
    }

    local M = {
    }

    new_class "C_BasePlayerPawn" {
        __index = function(self, key)
            if M[key] then return M[key] end
            if offsetof_t[key] then return offsetof_t[key](self) end
        end,
        __newindex = function(self, key, value)
            if offsetof_t[key] then return offsetof_t[key](self, value) end
        end
    }
end

new_class "CGameEntitySystem" {
    __index = {
        GetHighestEntityIndex = function(self)
            return ffi.cast("int*", ffi.cast("uintptr_t", self) + 0x1520)[0]
        end,
        GetEntityInstance = function(self, entindex)
            if entindex ~= nil and entindex <= 0x7FFE and bit.rshift(entindex, 9) <= 0x3F then
                local v2 = ffi.cast("uint64_t*", ffi.cast("uintptr_t", self) + 8 * bit.rshift(entindex, 9) + 16)[0]
                if v2 == 0 then return end

                local v3 = ffi.cast("uint32_t*", 120 * bit.band(entindex, 0x1FF) + v2)
                if v3 == nil then return end

                if bit.band(v3[4], 0x7FFF) == entindex then return ffi.cast("uint64_t*", v3)[0] end
            end
        end
    }
}

local CGameEntitySystem = ffi.cast("CGameEntitySystem**", ffi.cast("uintptr_t", create_interface("engine2.dll", "GameResourceServiceClientV001")) + 0x58)[0]

local function get_spectating_players()
    localplayer_index = client.GetLocalPlayerIndex()
    player_name = client.GetPlayerNameByIndex(localplayer_index)
    if not player_name then return end
    local_pawn = entities.GetLocalPawn()
    if not local_pawn then return {}, 0 end
    local_controller_index = local_pawn:GetPropEntity "m_hController":GetIndex()

    players, observing = {}, local_controller_index
    maxplayers = globals.MaxClients()

    for i = 1, maxplayers do
        local player_controller = entities.GetByIndex(i)
        if player_controller == nil or player_controller:GetClass() ~= "CCSPlayerController" then
            goto continue
        end

        player_pawn = player_controller:GetPropEntity "m_hPawn"
        if player_pawn == nil then goto continue end

        player_pawn_index = player_pawn:GetIndex()
        if player_pawn_index == nil then goto continue end

        player_pawn_instance = ffi.cast("C_BasePlayerPawn*", CGameEntitySystem:GetEntityInstance(player_pawn_index))
        if player_pawn_instance == nil then goto continue end

        observer_services = player_pawn_instance["m_pObserverServices"]
        if observer_services == nil then goto continue end

        observer_mode = observer_services["m_iObserverMode"]
        observer_target = entities.GetByIndex(tonumber(bit.band(observer_services["m_hObserverTarget"], 0x7fff)))

        if observer_target ~= nil and not player_pawn:IsAlive() and (observer_mode == 2 or observer_mode == 3) then
            observer_target_index = observer_target:GetPropEntity "m_hController":GetIndex()
            if observer_target_index == nil then goto continue end

            if players[observer_target_index] == nil then
                players[observer_target_index] = {}
            end

            if i == local_controller_index then
                observing = observer_target_index
            end

            table.insert(players[observer_target_index], i)
        end

        ::continue::
    end

    return players, observing
end

local victoryFlag = 0
local roundCounter = 0
local defeatFlag = 0

-- Обработчик начала раунда
local function OnRoundStart(event)
    if event:GetName() ~= "round_start" then return end
    
    victoryFlag = 0  -- Сброс флага при старте раунда
    defeatFlag = 0
    roundCounter = roundCounter + 1
end

-- Обработчик окончания раунда
local function OnRoundEnd(event)
    if event:GetName() ~= "round_end" then return end
    
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end
    
    local winningTeam = event:GetInt("winner")
    local playerTeam = localPlayer:GetTeamNumber()
    
    if winningTeam == playerTeam then
        victoryFlag = 1  -- Устанавливаем флаг при победе
        print("1"..victoryFlag)
    else
        defeatFlag = 1
        print("2"..defeatFlag)
    end
end

client.AllowListener("round_start")
client.AllowListener("round_end")
callbacks.Register("FireGameEvent", "RoundStartHandler", OnRoundStart)
callbacks.Register("FireGameEvent", "RoundEndHandler", OnRoundEnd)

local font_header = draw.CreateFont('Tahoma', 15, 400, false, false, false, 0, 0, 0, false)
local font_body = draw.CreateFont('Tahoma', 13, 5000, false, false, false, 0, 0, 0, false)

local is_dragging = false
local drag_offset_x, drag_offset_y = 0, 0
local window_x, window_y = 1620, 270
local mouse_down = false

local header_texture, tex_w, tex_h
do
    local png_data = http.Get("https://i.imgur.com/lgl4jPi.png")
    local img_rgba, w, h = common.DecodePNG(png_data)
    if img_rgba then
        header_texture = draw.CreateTexture(img_rgba, w, h)
        tex_w, tex_h = w, h
    end
end

local accent_color = {62, 62, 62, 255}
local entry_color = {68, 68, 68, 255}
local contrast_color = {41, 41, 41, 255}
local outline_color = {84, 84, 84, 255}

local header_width = 300
local entry_width = 276
local header_height = 19
local entry_height = 23

local function draw_speclist_header(x, y)
    if spectype == 0 then return end
    if not spec_check:GetValue() then return end
    if not speclist_on then return end
    if header_texture then
        local aspect_ratio = tex_h / tex_w
        local draw_height = header_width * aspect_ratio
        draw.SetTexture(header_texture)
        draw.FilledRect(x, y, x + header_width, y + draw_height)
        draw.SetTexture(nil)
    else
        draw.Color(unpack(accent_color))
        draw.FilledRect(x, y, x + header_width, y + header_height)
    end

    draw.SetFont(font_header)
    local text = 'SPECTATOR LIST'
    local tw, th = draw.GetTextSize(text)
    local text_x = x + (header_width * 0.5) - (tw * 0.5)
    local text_y = y + (header_height * 0.5) - (th * 0.5) + 3

    draw.Color(0, 0, 0, 200)
    draw.Text(text_x + 1, text_y + 2, text)
    draw.Text(text_x - 1, text_y + 2, text)
    

	local lua_damage_color_r2, lua_damage_color_g2, lua_damage_color_b2, lua_damage_color_z2 = spec_color:GetValue()
    draw.Color(lua_damage_color_r2, lua_damage_color_g2, lua_damage_color_b2, lua_damage_color_z2)
    draw.Text(text_x, text_y + 1, text)
end

local function draw_speclist_body(x, y)
    if spectype == 0 then return end
    if defeatFlag == 1 then return end
    if victoryFlag == 1 then return end
    if not speclist_on then return end
    localplayer_index = client.GetLocalPlayerIndex()
    player_name = client.GetPlayerNameByIndex(localplayer_index)
    if not player_name then return end
    if not spec_check:GetValue() then return end

    spectators, player = get_spectating_players()
    local spec_list = spectators[player] or {}
    if #spec_list == 0 then return end

    local body_y = y + header_height + 6
    local list_height = #spec_list * entry_height

    for i, idx in ipairs(spec_list) do
        local entry_y = body_y + (i - 1) * entry_height
        
        draw.Color(unpack(i % 2 == 1 and contrast_color or entry_color))
        draw.FilledRect(x + 2, entry_y, x + 2 + entry_width, entry_y + entry_height)

        draw.SetFont(font_body)
        local ent = entities.GetByIndex(idx)
        if ent then
            local name = ent:GetPropString("m_iszPlayerName")
            local text_y_offset = 7

            draw.Color(0, 0, 0, 200)
            draw.Text(x + 7, entry_y + text_y_offset + 1, name)
            
            draw.Color(255, 255, 255, 220)
            draw.Text(x + 6, entry_y + text_y_offset, name)
        end
    end

    draw.Color(unpack(outline_color))
    draw.OutlinedRect(x + 2, body_y, x + 2 + entry_width, body_y + list_height)
end

local function handle_mouse()
    if spectype == 0 then return end
    if not spec_check:GetValue() then return end
    if not speclist_on then return end
    local mouse_x, mouse_y = input.GetMousePos()
    
    if input.IsButtonDown(1) then
        if not mouse_down then
            if mouse_x >= window_x and mouse_x <= window_x + header_width and
               mouse_y >= window_y and mouse_y <= window_y + header_height then
                is_dragging = true
                drag_offset_x = mouse_x - window_x
                drag_offset_y = mouse_y - window_y
            end
            mouse_down = true
        end
    else
        mouse_down = false
        is_dragging = false
    end

    if is_dragging then
        window_x = mouse_x - drag_offset_x
        window_y = mouse_y - drag_offset_y
    end
end

local function DrawSpectatorList()
    if spectype == 1 then return end
    if defeatFlag == 1 then return end
    if victoryFlag == 1 then return end
    if not speclist_on then return end
    local localplayer_index = client.GetLocalPlayerIndex()
    local player_name = client.GetPlayerNameByIndex(localplayer_index)
    if not player_name then return end
    if not spec_check:GetValue() then return end

    local active = {}
    local spectators, player = get_spectating_players()
    local screen_width, screen_height = draw.GetScreenSize()
    local maxplayers = globals.MaxClients()
    local lua_damage_color_r2, lua_damage_color_g2, lua_damage_color_b2, lua_damage_color_z2 = spec_color:GetValue()
    
    local offset2 = 0
    if ui_check77:GetValue() and startX > 1740 and startY < 30 then
        offset2 = 35
    else
        offset2 = 0
    end

    local frametime = globals.FrameTime()
    for i = 1, maxplayers do
        if not active[i] then
            table.insert(active, i, {
                alpha = 0,
                active = false
            })
        end
    end

    for i = 1, maxplayers do
        if active[i].active then
            active[i].active = false
        end
    end

    local actives = 0
    for _, idx in ipairs(spectators[player] or {}) do
        active[idx].active = true
        actives = actives + 1
    end

    local offset = 0
    for i = #active, 1, -1 do
        local value = active[i]
        value.alpha = value.active and 1 or 0

        if value.alpha > 0 then
            local ent = entities.GetByIndex(i)
            if ent then
                local name = ent:GetPropString("m_iszPlayerName")
                local speclist_text = name .. " >> " .. player_name
                local Tw, Th = draw.GetTextSize(speclist_text)
                local Tw2, Th2 = draw.GetTextSize(name)
                
                local x = screen_width - Tw - 10
                local y = 10 + offset + offset2

                local x2 = screen_width - Tw2 - 10
                
                draw.Color(lua_damage_color_r2, lua_damage_color_g2, lua_damage_color_b2, lua_damage_color_z2)
				if check_name:GetValue() then
                    draw.TextShadow(x, y, speclist_text)
				else
				    draw.TextShadow(x2, y, name)
                end
                
                offset = offset + Th + 8
            end
        end
    end
end

local function RegisterCallbacks()
        callbacks.Register('Draw', function()
            handle_mouse()
            DrawSpectatorList()
            draw_speclist_header(window_x, window_y)
            draw_speclist_body(window_x, window_y)
        end)
        return {
            { name = "Draw", reference = my_draw_callback_ref }
        }
    end

    local function Cleanup()
        active = {}
        lua_damage_color_r2, lua_damage_color_g2, lua_damage_color_b2, lua_damage_color_z2 = nil, nil, nil, nil -- release reference
        my_draw_callback_ref = nil
        

        print("Cleanup1 called in iwebz.lua")
        spec_check:SetInvisible(true)
        spec_color:SetInvisible(true)
        speclist_on = false
    end

    local function get_enemy_players()
        local local_player_index = client.GetLocalPlayerIndex()
        local local_player = entities.GetByIndex(local_player_index)
    
        if not local_player then return {} end
    
        local enemy_players = {}
        local max_players = globals.MaxClients()
    
        for i = 1, max_players do
            local player = entities.GetByIndex(i)
            
            if player and player:IsAlive() and player:GetTeamNumber() ~= local_player:GetTeamNumber() then
                table.insert(enemy_players, player)
            end
        end
    
        return enemy_players
    end
            
    -- Обработчик окончания раунда
local function OnRoundEnd(event)
    if event:GetName() ~= "round_end" then return end

    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end

    local winningTeam = event:GetInt("winner")
    local playerTeam = localPlayer:GetTeamNumber()

    -- Проверяем состояние всех врагов
    local allEnemiesDead = true
    for i = 1, globals.MaxClients() do
        local enemy = entities.GetByIndex(i)
        if enemy and enemy:IsAlive() and enemy:GetTeamNumber() ~= playerTeam then
            allEnemiesDead = false
            break
        end
    end 

    -- Функция для проверки состояния врагов и установки флага победы
    local function CheckEnemiesAndSetVictoryFlag()
        local enemies = get_enemy_players() -- Получаем всех врагов
        local allEnemiesDead = true

        -- Проверяем состояние каждого врага
        for _, enemy in ipairs(enemies) do
            if enemy:IsAlive() then
                allEnemiesDead = false
                break
            end
        end

        if allEnemiesDead then
            victoryFlag = 1 -- Устанавливаем флаг победы
            print("Victory Flag Set: " .. victoryFlag)
        end
    end

CheckEnemiesAndSetVictoryFlag()

    if winningTeam == playerTeam or allEnemiesDead then
        victoryFlag = 1 -- Устанавливаем флаг при победе или если все враги мертвы
        print("Victory Flag Set: " .. victoryFlag)
    else
        defeatFlag = 1
        print("Defeat Flag Set: " .. defeatFlag)
    end
end


    return {
        RegisterCallbacks = RegisterCallbacks,
        Cleanup = Cleanup
    }

