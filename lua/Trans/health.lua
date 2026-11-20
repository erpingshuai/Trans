local Trans      = require 'Trans'
local health, fn = vim.health, vim.fn

local ok         = health.ok
local warn       = health.warn
local error      = health.error
local has        = fn.has
local executable = fn.executable

local function check_neovim_version()
    if has 'nvim-0.9' == 1 then
        ok [[You have [neovim-nightly] ]]
    else
        warn [[Trans Title requires Neovim 0.9 or newer
        See neovim-nightly: [https://github.com/neovim/neovim/releases/tag/nightly]
        ]]
    end
end

local function check_binary_dependencies()
    local binary_dependencies = {
        'curl',
        ({
            win    = nil,
            mac    = 'say',
            linux  = 'festival',
            termux = 'termux-tts-speak',
        })[Trans.system],
    }

    for _, dep in ipairs(binary_dependencies) do
        if executable(dep) == 1 then
            ok(string.format('Binary dependency [%s] is installed', dep))
        else
            error(string.format('Binary dependency [%s] is not installed', dep))
        end
    end
end

local function check_llm()
    local backend = Trans.backend.llm
    ok(string.format('LLM model: %s', backend.model or 'unknown'))
    ok(string.format('LLM endpoint: %s', backend.uri or 'unknown'))

    if not backend.uri or backend.uri == '' then
        error 'LLM endpoint is empty, please configure Trans.json'
    end
end

local function check_configure_file()
    local path = fn.expand(Trans.conf.dir .. '/Trans.json')
    if not fn.filereadable(path) then
        warn(string.format(
            'Backend configuration file [%s] not found, using default LLM backend',
            path
        ))
        return
    end

    local file = io.open(path, 'r')
    local valid = file and pcall(vim.json.decode, file:read '*a')

    if valid then
        ok(string.format([[Backend configuration file [%s] found and valid ]], path))
    else
        error(string.format(
            [[Backend configuration file [%s] invalid
        Please check the doc in github: [https://github.com/JuanZoran/Trans.nvim]
        ]],
            path
        ))
    end
end

local function check()
    check_neovim_version()
    check_configure_file()
    check_llm()
    check_binary_dependencies()
end

return { check = check }
