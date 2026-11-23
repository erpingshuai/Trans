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
        return
    end

    local host, port = Trans.server.parse_uri(backend.uri)
    local manageable =
        backend.auto_start ~= false
        and host and Trans.server.is_local(host)
        and port ~= 11434

    local status = Trans.server.status()
    if status.running then
        ok 'LLM service is running'
    elseif not manageable then
        warn 'LLM service is external (auto_start = false or non-local endpoint); Trans will not start it'
    else
        warn('Local LLM service is not running yet; it will start automatically on first :Translate. '
            .. 'Log: ' .. tostring(status.log))
    end

    -- Only a locally managed llama.cpp service needs a GGUF model and binary.
    if manageable then
        if status.model then
            ok(string.format('GGUF model: %s', status.model))
        else
            warn(string.format('GGUF model not found: %s/%s', status.model_dir, status.model_file))
            if status.auto_download_model then
                warn('The model will be downloaded automatically on :TransInstall or first :Translate')
            else
                warn('auto_download_model = false; download the model manually or set llm.model_dir/model_path')
            end
        end

        if status.server then
            ok(string.format('llama-server: %s', status.server))
        elseif backend.auto_download ~= false then
            warn('llama-server not installed yet; it will be downloaded automatically on :TransInstall or first :Translate')
        else
            warn('llama-server not found and auto_download is disabled; install llama.cpp or set llm.server_bin')
        end
    end
end


---Report whether baidu / youdao fallbacks have credentials.
local function check_online_backends()
    local states = Trans.backend.states or {}
    local names = { baidu = '百度', youdao = '有道' }

    for _, name in ipairs { 'baidu', 'youdao' } do
        local state = states[name]
        local label = names[name]

        if state == 'configured' then
            ok(string.format('%s API: configured', label))
        elseif state == 'disabled' then
            warn(string.format('%s API: credentials found but disable = true', label))
        else
            error(string.format(
                '%s API: app_id / app_passwd not configured. '
                    .. 'Edit %s/Trans.json and set app_id, app_passwd, disable = false. '
                    .. 'Without it Trans cannot fall back when the local model is unavailable.',
                label,
                Trans.conf.dir
            ))
        end
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
    check_online_backends()
    check_binary_dependencies()
end

return { check = check }
