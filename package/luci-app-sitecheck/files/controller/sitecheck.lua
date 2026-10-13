module("luci.controller.sitecheck", package.seeall)

function index()
    if not nixio.fs.access("/usr/libexec/sitecheck-check") then return end
    entry({"admin", "services", "sitecheck"}, template("sitecheck/index"), _("Site_Checker"), 85).dependent = true
    entry({"admin", "services", "sitecheck", "check"}, call("action_check")).leaf = true
    entry({"admin", "services", "sitecheck", "get_config"}, call("action_get_config")).leaf = true
    entry({"admin", "services", "sitecheck", "save_config"}, call("action_save_config")).leaf = true
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
        if s.domain and #s.domain > 0 then domains[#domains + 1] = { name = s.name or s.domain, domain = s.domain } end
    end)
    return #domains > 0 and domains or defaults()
end

function action_get_config()
    local http = require("luci.http")
    http.prepare_content("application/json")
    http.write_json({ domains = read_domains() })
end

local function valid_url(url)
    return type(url) == "string" and #url <= 255 and
        (url:match("^https://[%w%.%-]+[%w%-%._~:/?#%[%]@!$&'()*+,;=%%]*$") or
         url:match("^http://[%w%.%-]+[%w%-%._~:/?#%[%]@!$&'()*+,;=%%]*$"))
end

function action_check()
    local http = require("luci.http")
    local json = require("luci.jsonc")
    local domains = json.parse(http.formvalue("domains") or "[]")
    if type(domains) ~= "table" then
        http.status(400, "Bad Request"); http.prepare_content("application/json")
        http.write_json({ error = "Некорректный список доменов" }); return
    end
    local safe = {}
    for _, item in ipairs(domains) do
        if #safe >= 30 then break end
        if type(item) == "table" and valid_url(item.domain) then
            safe[#safe + 1] = { name = tostring(item.name or item.domain):sub(1, 80), domain = item.domain }
        end
    end
    local results = {}
    for _, item in ipairs(safe) do
        local pipe = io.popen("/usr/libexec/sitecheck-check " .. string.format("%q", item.domain) .. " 2>/dev/null")
        local output = pipe and pipe:read("*a") or ""
        if pipe then pipe:close() end
        local ok, ms, code = output:match("^(%d+)|(%d+)|(%d+)")
        results[#results + 1] = { name = item.name, domain = item.domain, ok = ok == "1",
            latency_ms = tonumber(ms), http_code = tonumber(code) }
    end
    http.prepare_content("application/json")
    http.write_json({ results = results, checked_at = os.date("%Y-%m-%d %H:%M:%S") })
end

function action_save_config()
    local http = require("luci.http")
    local json = require("luci.jsonc")
    local domains = json.parse(http.formvalue("domains") or "[]")
    if type(domains) ~= "table" or #domains < 1 or #domains > 30 then
        http.status(400, "Bad Request"); http.prepare_content("application/json")
        http.write_json({ error = "Нужен список от 1 до 30 сайтов" }); return
    end
    local cleaned = {}
    for _, item in ipairs(domains) do
        if type(item) == "table" and type(item.name) == "string" and valid_url(item.domain) then
            cleaned[#cleaned + 1] = { name = item.name:sub(1, 80), domain = item.domain }
        end
    end
    if #cleaned == 0 then
        http.status(400, "Bad Request"); http.prepare_content("application/json")
        http.write_json({ error = "Не найдено корректных URL" }); return
    end
    local uci = require("luci.model.uci").cursor()
    uci:delete_all("sitecheck", "site")
    for _, item in ipairs(cleaned) do
        local section = uci:add("sitecheck", "site")
        uci:set("sitecheck", section, "name", item.name)
        uci:set("sitecheck", section, "domain", item.domain)
    end
    uci:save("sitecheck"); uci:commit("sitecheck")
    http.prepare_content("application/json")
    http.write_json({ ok = true, count = #cleaned })
end
