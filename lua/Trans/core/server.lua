---Auto-start the local OpenAI-compatible llama.cpp server.
---
---This module never downloads anything. The user downloads the GGUF model and
---installs llama.cpp themselves (see README). On first use Trans only checks
---that both already exist, and if so starts the service in the background.
local Trans = require 'Trans'

local M = {}

local uv = vim.uv or vim.loop

local LLAMA_VERSION = 'b12559'
local MODEL_FILE = 'qwen2.5-0.5b-instruct-q4_k_m.gguf'

local state = {
    starting  = false,
    ready     = false,
    callbacks = {},
    missing_notified = false,
}

---@param message string
---@param level integer?
local function notify(message, level)
    vim.notify('Trans: ' .. message, level or vim.log.levels.INFO)
end

---Run all queued callbacks once we know whether requests can be sent.
---@param ok boolean
local function flush(ok)
    local callbacks = state.callbacks
    state.callbacks = {}
    for _, callback in ipairs(callbacks) do
        local called, err = pcall(callback, ok)
        if not called then
            notify('内部错误: ' .. tostring(err), vim.log.levels.ERROR)
        end
    end
end

---@param path string?
---@return string?
local function expand(path)
    if type(path) ~= 'string' or path == '' then
        return nil
    end
    return vim.fn.expand(path)
end

---@return string
local function default_model_path()
    return vim.fn.expand('~/models/qwen2.5-0.5b-instruct/' .. MODEL_FILE)
end

---@return string?
local function managed_server()
    local dir = vim.fn.stdpath 'data' .. '/Trans/llama/llama-' .. LLAMA_VERSION
    for _, name in ipairs { 'llama-server', 'llama-server.exe' } do
        local path = dir .. '/' .. name
        if vim.fn.executable(path) == 1 then
            return path
        end
    end
end

---Parse an OpenAI compatible endpoint into host, port and health URL.
---@param uri string?
---@return string? host
---@return integer? port
---@return string? health_url
function M.parse_uri(uri)
    if type(uri) ~= 'string' then
        return nil
    end

    local scheme, host, port = uri:match '^(https?)://([^/:]+):(%d+)'
    if not scheme then
        scheme, host = uri:match '^(https?)://([^/:]+)'
        port = scheme == 'https' and 443 or 80
    end

    if not scheme or not host then
        return nil
    end

    port = tonumber(port)
    if not port then
        return nil
    end

    local health_host = host
    if host == '0.0.0.0' or host == '::' then
        health_host = '127.0.0.1'
    end

    return host, port, ('%s://%s:%d/health'):format(scheme, health_host, port)
end

---@param host string
---@return boolean
function M.is_local(host)
    return host == '127.0.0.1'
        or host == 'localhost'
        or host == '0.0.0.0'
        or host == '::1'
        or host == '::'
end

---Find a llama-server binary. No downloads are performed here.
---@param configured string?
---@return string?
function M.find_server(configured)
    local path = expand(configured)
    if path and vim.fn.executable(path) == 1 then
        return path
    end

    local managed = managed_server()
    if managed then
        return managed
    end

    local exe = vim.fn.exepath 'llama-server'
    if exe ~= '' then
        return exe
    end

    local matches = vim.fn.glob(vim.fn.expand '~/tools/llama/*/llama-server', false, true)
    for _, candidate in ipairs(matches) do
        if vim.fn.executable(candidate) == 1 then
            return candidate
        end
    end
end

---Find the GGUF model file. No downloads are performed here.
---@param configured string?
---@return string?
function M.find_model(configured)
    local path = expand(configured)
    if path and vim.fn.filereadable(path) == 1 then
        return path
    end

    local default = default_model_path()
    if vim.fn.filereadable(default) == 1 then
        return default
    end

    local managed = vim.fn.stdpath 'data' .. '/Trans/models/' .. MODEL_FILE
    if vim.fn.filereadable(managed) == 1 then
        return managed
    end
end

---Explain what the user must provide when a local service cannot be started.
---@param model string?
---@param server string?
local function notify_missing(model, server)
    if state.missing_notified then
        return
    end
    state.missing_notified = true

    local lines = { '本地服务缺少必要文件，不会自动启动：' }

    if not model then
        lines[#lines + 1] = '  1. 未找到 GGUF 模型，请把模型放到：'
        lines[#lines + 1] = '     ' .. default_model_path()
        lines[#lines + 1] = '     或在 Trans.json 中设置 llm.model_path。下载方法见 README。'
    end

    if not server then
        lines[#lines + 1] = '  2. 未找到 llama-server，请安装 llama.cpp 并放入 PATH，'
        lines[#lines + 1] = '     ~/tools/llama/*/ 或 Trans.json 的 llm.server_bin。'
    end

    notify(table.concat(lines, '\n'), vim.log.levels.ERROR)
end

---Check the llama.cpp health endpoint.
---@param url string
---@param callback fun(ok: boolean)
local function check_health(url, callback)
    local finished = false
    local function finish(ok)
        if finished then
            return
        end
        finished = true
        callback(ok)
    end

    local job = vim.fn.jobstart({ 'curl', '-fsS', '--max-time', '2', url }, {
        stdout = '',
        stderr = '',
        on_exit = function(_, code)
            finish(code == 0)
        end,
    })

    if job <= 0 then
        finish(false)
        return
    end

    vim.defer_fn(function()
        if not finished then
            pcall(vim.fn.jobstop, job)
            finish(false)
        end
    end, 3000)
end

---Start llama-server detached from Neovim.
---@param server string
---@param model string
---@param host string
---@param port integer
---@param ctx integer
---@param threads integer
---@param log_path string
---@return integer? pid
---@return string? error
local function spawn(server, model, host, port, ctx, threads, log_path)
    local args = {
        '-m', model,
        '--host', host,
        '--port', tostring(port),
        '-c', tostring(ctx),
        '-t', tostring(threads),
    }

    if Trans.system == 'win' then
        local job = vim.fn.jobstart(vim.list_extend({ server }, args), {
            detach = true,
            stdout = log_path,
            stderr = log_path,
        })
        if job <= 0 then
            return nil, 'jobstart failed'
        end
        return job
    end

    local out_fd, out_err = uv.fs_open(log_path, 'a', 420)
    if not out_fd then
        return nil, out_err
    end

    local in_fd = uv.fs_open('/dev/null', 'r', 0)
    if not in_fd then
        uv.fs_close(out_fd)
        return nil, 'cannot open /dev/null'
    end

    local handle, pid = uv.spawn(server, {
        args = args,
        stdio = { in_fd, out_fd, out_fd },
        cwd = vim.fn.fnamemodify(server, ':h'),
        detached = true,
    })

    uv.fs_close(in_fd)
    uv.fs_close(out_fd)

    if not handle then
        return nil, pid
    end

    handle:unref()
    handle:close()
    return pid
end

---Ensure the local LLM server is running before a translation request.
---All queued callbacks run once the service is ready (or decided not manageable),
---so the first translation never races a cold start.
---@param callback? fun(ok: boolean) called when it is safe to send requests
---@param opts? { quiet?: boolean }
function M.ensure_started(callback, opts)
    opts = opts or {}

    if type(callback) == 'function' then
        state.callbacks[#state.callbacks + 1] = callback
    end

    local backend = Trans.backend.llm
    local host, port, health_url = M.parse_uri(backend.uri)

    -- Only manage our own local llama.cpp service. External services (Ollama,
    -- LM Studio, a remote host or auto_start = false) are used as they are.
    local manageable =
        vim.tbl_contains(Trans.backend.all_name, 'llm')
        and backend.auto_start ~= false
        and host and port and health_url
        and M.is_local(host)
        and port ~= 11434

    if not manageable or state.ready then
        flush(true)
        return
    end

    if state.starting then
        return
    end
    state.starting = true

    check_health(health_url, function(ok)
        if ok then
            state.ready = true
            state.starting = false
            flush(true)
            return
        end

        local model = M.find_model(backend.model_path)
        local server = M.find_server(backend.server_bin)
        if not model or not server then
            state.starting = false
            notify_missing(model, server)
            flush(true) -- still try baidu / youdao fallback
            return
        end

        local ctx = tonumber(backend.ctx) or 4096
        local threads = tonumber(backend.threads) or 0
        if threads <= 0 then
            local cpus = uv.cpu_info()
            threads = math.max(1, math.min(8, cpus and #cpus or 4))
        end

        local log_path = expand(backend.log_path)
            or (vim.fn.stdpath 'cache' .. '/Trans-llm.log')
        vim.fn.mkdir(vim.fn.fnamemodify(log_path, ':h'), 'p')

        local pid, err = spawn(server, model, host, port, ctx, threads, log_path)
        if not pid then
            state.starting = false
            notify(('启动本地模型失败: %s\n日志: %s'):format(tostring(err), log_path), vim.log.levels.ERROR)
            flush(true)
            return
        end

        local timeout = (tonumber(backend.start_timeout) or 120) * 1000
        local deadline = uv.hrtime() + timeout * 1000000

        local function poll()
            if uv.hrtime() > deadline then
                state.starting = false
                notify('本地模型启动超时，请查看日志: ' .. log_path, vim.log.levels.ERROR)
                flush(true)
                return
            end

            check_health(health_url, function(healthy)
                if healthy then
                    state.ready = true
                    state.starting = false
                    if not opts.quiet then
                        notify('本地模型已启动: ' .. health_url, vim.log.levels.INFO)
                    end
                    flush(true)
                else
                    vim.defer_fn(poll, 300)
                end
            end)
        end

        vim.defer_fn(poll, 300)
    end)
end

---Short status used by :checkhealth.
---@return { running: boolean, uri: string?, model: string?, server: string?, log: string? }
function M.status()
    local backend = Trans.backend.llm
    local _, _, health_url = M.parse_uri(backend.uri)
    local running = false

    if health_url then
        vim.fn.system({ 'curl', '-fsS', '--max-time', '2', health_url })
        running = vim.v.shell_error == 0
    end

    return {
        running = running,
        uri = backend.uri,
        model = M.find_model(backend.model_path),
        server = M.find_server(backend.server_bin),
        log = expand(backend.log_path) or (vim.fn.stdpath 'cache' .. '/Trans-llm.log'),
    }
end

return M
