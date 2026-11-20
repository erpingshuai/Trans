local Trans = require 'Trans'


---@class TransBackend
---@field no_wait? boolean whether need to wait for the result
---@field all_name string[] @all backend name
---@field name string @backend name
---@field name_zh string @backend name in Chinese

---@class TransOnlineBackend: TransBackend
---@field uri string @request uri
---@field method 'get' | 'post' @request method
---@field formatter fun(body: table, data: TransData): TransResult|false|nil @formatter
---@field get_query fun(data: TransData): table<string, string>|table @get query or request body
---@field header? table<string, string> | fun(data: TransData): table<string, string> @request header
---@field timeout? integer @request timeout in seconds
---@field debug? fun(body: table?, output: RequestResult?) @debug


local conf = Trans.conf
-- INFO :Parse online engine keys config file
local path = conf.dir .. '/Trans.json'
local file = io.open(path, 'r')


local user_conf = {}
if file then
    local content = file:read '*a'
    file:close()

    local ok, decoded = pcall(vim.json.decode, content)
    if ok and type(decoded) == 'table' then
        -- INFO :Support both array format [{ name = 'llm', ... }]
        --        and object format { llm = { ... } }
        if decoded.name then
            user_conf[decoded.name] = decoded
        else
            for key, config in pairs(decoded) do
                if type(config) == 'table' then
                    local name = config.name or (type(key) == 'string' and key or nil)
                    if name then
                        config.name = name
                        user_conf[name] = config
                    end
                end
            end
        end
    end
end


---Check whether an API backend has enough credentials configured
---@param config table?
---@return boolean
local function has_credentials(config)
    return config ~= nil and config.disable ~= true and config.app_id ~= nil and config.app_passwd ~= nil
end


local all_name = {}
local seen = {}

---Register a backend if it is enabled
---@param name string
---@param enabled boolean
local function register(name, enabled)
    if enabled and not seen[name] then
        seen[name] = true
        all_name[#all_name + 1] = name
    end
end


-- INFO :LLM is the primary backend and is enabled by default.
register('llm', not (user_conf.llm and user_conf.llm.disable))

-- INFO :Online API backends are optional fallbacks and only enabled when configured.
register('baidu', has_credentials(user_conf.baidu))
register('youdao', has_credentials(user_conf.youdao))

-- INFO :Allow extra user defined backends (a matching module must exist).
for name, config in pairs(user_conf) do
    if not seen[name] and config.disable ~= true then
        local ok = pcall(require, 'Trans.backend.' .. name)
        if ok then
            register(name, true)
        end
    end
end


---@class TransBackends
---@field all_name string[] all backend names

---@class Trans
---@field backend TransBackends
return setmetatable({
    all_name = all_name,
}, {
    __index = function(self, name)
        ---@type TransBackend
        local backend = require('Trans.backend.' .. name)

        for key, value in pairs(user_conf[name] or {}) do
            backend[key] = value
        end

        self[name] = backend
        return backend
    end,
})
