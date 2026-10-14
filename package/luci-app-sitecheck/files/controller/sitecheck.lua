module("luci.controller.sitecheck", package.seeall)

function index()
    if not nixio.fs.access("/usr/libexec/sitecheck-check") then return end
    entry({"admin", "services", "sitecheck"}, template("sitecheck/index"), _("Site_Checker"), 85).dependent = true
    entry({"admin", "services", "sitecheck", "check"}, call("action_check")).leaf = true
    entry({"admin", "services", "sitecheck", "check_zapret"}, call("action_check_zapret")).leaf = true
    entry({"admin", "services", "sitecheck", "get_config"}, call("action_get_config")).leaf = true
    entry({"admin", "services", "sitecheck", "save_config"}, call("action_save_config")).leaf = true
    entry({"admin", "services", "sitecheck", "save_settings"}, call("action_save_settings")).leaf = true
end

local function defaults()
    return {
        { name = "YouTube", domain = "https://www.youtube.com/" },
        { name = "WhatsApp", domain = "https://web.whatsapp.com/" },
        { name = "Telegram", domain = "https://web.telegram.org/" },
        { name = "Instagram", domain = "https://www.instagram.com/" },
        { name = "TikTok", domain = "https://www.tiktok.com/" },
        { name = "Discord", domain = "https://discord.com/" }
    }
end

local function read_domains()
    local uci = require("luci.model.uci").cursor()
    local domains = {}
    uci:foreach("sitecheck", "site", function(s)
        if s.domain and #s.domain > 0 then
            domains[#domains + 1] = { name = s.name or s.domain, domain = s.domain }
        end
    end)
    return #domains > 0 and domains or defaults()
end

function action_get_config()
    local http = require("luci.http")
    local uci = require("luci.model.uci").cursor()
    http.prepare_content("application/json")
    http.write_json({
        domains = read_domains(),
        auto_refresh = uci:get("sitecheck", "settings", "auto_refresh") == "1"
    })
end

function action_save_settings()
    local http = require("luci.http")
    local uci = require("luci.model.uci").cursor()
    local enabled = http.formvalue("auto_refresh") == "1" and "1" or "0"
    uci:set("sitecheck", "settings", "auto_refresh", enabled)
    uci:save("sitecheck")
    uci:commit("sitecheck")
    http.prepare_content("application/json")
    http.write_json({ ok = true, auto_refresh = enabled == "1" })
end

local function valid_url(url)
    return type(url) == "string" and #url <= 255 and
        (url:match("^https://[%w%.%-]+[%w%-%._~:/?#%[%]@!$&'()*+,;=%%]*$") or
         url:match("^http://[%w%.%-]+[%w%-%._~:/?#%[%]@!$&'()*+,;=%%]*$"))
end

local function decode_domains(http, json, max_count)
    local domains = json.parse(http.formvalue("domains") or "[]")
    if type(domains) ~= "table" then
        http.status(400, "Bad Request")
        http.prepare_content("application/json")
        http.write_json({ error = "Некорректный список доменов" })
        return nil
    end
    local safe = {}
    for _, item in ipairs(domains) do
        if #safe >= max_count then break end
        if type(item) == "table" and valid_url(item.domain) then
            safe[#safe + 1] = { name = tostring(item.name or item.domain):sub(1, 80), domain = item.domain }
        end
    end
    return safe
end

local function run_check_script(script_path, url)
    local pipe = io.popen(script_path .. " " .. string.format("%q", url) .. " 2>/dev/null")
    local output = pipe and pipe:read("*a") or ""
    if pipe then pipe:close() end
    local ok, ms, code = output:match("^(%d+)|(%d+)|(%d+)")
    return ok == "1", tonumber(ms), tonumber(code)
end

function action_check()
    local http = require("luci.http")
    local json = require("luci.jsonc")
    local safe = decode_domains(http, json, 30)
    if not safe then return end
    local results = {}
    for _, item in ipairs(safe) do
        local ok, ms, code = run_check_script("/usr/libexec/sitecheck-check", item.domain)
        results[#results + 1] = { name = item.name, domain = item.domain, ok = ok, latency_ms = ms, http_code = code }
    end
    http.prepare_content("application/json")
    http.write_json({ results = results, checked_at = os.date("%Y-%m-%d %H:%M:%S") })
end

function action_check_zapret()
    local http = require("luci.http")
    local pipe = io.popen("/usr/libexec/sitecheck-system-sites 2>/dev/null")
    local output = pipe and pipe:read("*a") or ""
    local command_ok = false
    if pipe then
        local a, b, c = pipe:close()
        command_ok = a == true
    end

    local results = {}
    for line in output:gmatch("[^\r\n]+") do
        local idx, name, url, ok, ms, code = line:match("^(%d+)|([^|]+)|([^|]+)|([01])|(%d+)|(%d+)$")
        if idx then
            results[#results + 1] = {
                name = name,
                domain = url,
                ok = ok == "1",
                latency_ms = tonumber(ms),
                http_code = tonumber(code)
            }
        end
    end

    if not command_ok and #results == 0 then
        http.status(500, "Internal Server Error")
        http.prepare_content("application/json")
        http.write_json({ error = "Не удалось выполнить проверку Zapret Manager. Проверьте curl и права на /usr/libexec/sitecheck-system-sites." })
        return
    end

    http.prepare_content("application/json")
    http.write_json({ results = results, checked_at = os.date("%Y-%m-%d %H:%M:%S") })
end

function action_save_config()
    local http = require("luci.http")
    local json = require("luci.jsonc")
    local domains = json.parse(http.formvalue("domains") or "[]")
    if type(domains) ~= "table" or #domains < 1 or #domains > 30 then
        http.status(400, "Bad Request")
        http.prepare_content("application/json")
        http.write_json({ error = "Нужен список от 1 до 30 сайтов" })
        return
    end

    local cleaned = {}
    for _, item in ipairs(domains) do
        if type(item) == "table" and type(item.name) == "string" and valid_url(item.domain) then
            cleaned[#cleaned + 1] = { name = item.name:sub(1, 80), domain = item.domain }
        end
    end
    if #cleaned == 0 then
        http.status(400, "Bad Request")
        http.prepare_content("application/json")
        http.write_json({ error = "Не найдено корректных URL" })
        return
    end

    local uci = require("luci.model.uci").cursor()
    uci:delete_all("sitecheck", "site")
    for _, item in ipairs(cleaned) do
        local section = uci:add("sitecheck", "site")
        uci:set("sitecheck", section, "name", item.name)
        uci:set("sitecheck", section, "domain", item.domain)
    end
    uci:save("sitecheck")
    uci:commit("sitecheck")
    http.prepare_content("application/json")
    http.write_json({ ok = true, count = #cleaned })
end
