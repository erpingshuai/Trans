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
local RELEASE_BASE = 'https://github.com/ggml-org/llama.cpp/releases/download'
local DOWNLOAD_MIN_SIZE = 1024 * 1024 -- ignore truncated archives

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

---@return string
local function managed_root()
    return vim.fn.stdpath 'data' .. '/Trans/llama'
end

---@return string?
local function managed_server()
    local dir = managed_root() .. '/llama-' .. LLAMA_VERSION
    for _, name in ipairs { 'llama-server', 'llama-server.exe' } do
        local path = dir .. '/' .. name
        if vim.fn.executable(path) == 1 then
            return path
        end
    end

    -- Also accept a manually unpacked or custom-version release.
    for _, name in ipairs { 'llama-server', 'llama-server.exe' } do
        local matches = vim.fn.glob(managed_root() .. '/*/' .. name, false, true)
        for _, path in ipairs(matches) do
            if vim.fn.executable(path) == 1 then
                return path
            end
        end
    end
end

---Map the current OS/architecture to an official llama.cpp release asset.
---Only the server binary is downloaded; the GGUF model is always provided by
---the user.
---@return string? asset
---@return string? ext
local function platform_asset()
    local uname = uv.os_uname()
    local sys = (uname.sysname or ''):lower()
    local machine = (uname.machine or ''):lower()

    local arch
    if machine == 'x86_64' or machine == 'amd64' or machine == 'x64' then
        arch = 'x64'
    elseif machine == 'aarch64' or machine == 'arm64' then
        arch = 'arm64'
    end

    if not arch then
        return nil
    end

    if sys == 'linux' then
        return ('llama-%s-bin-ubuntu-%s.tar.gz'):format(LLAMA_VERSION, arch), '.tar.gz'
    elseif sys == 'darwin' then
        return ('llama-%s-bin-macos-%s.tar.gz'):format(LLAMA_VERSION, arch), '.tar.gz'
    elseif sys == 'windows_nt' or sys == 'windows' then
        return ('llama-%s-bin-win-cpu-%s.zip'):format(LLAMA_VERSION, arch), '.zip'
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

---Download and unpack the official llama.cpp release for this platform.
---The GGUF model is deliberately not downloaded.
---@param backend table
---@param callback fun(ok: boolean, err: string?)
local function download_server(backend, callback)
    local asset, ext = platform_asset()
    if not asset then
        callback(false, '当前系统/架构没有可用的 llama.cpp 预编译包，请手动设置 llm.server_bin')
        return
    end

    local url = backend.server_url
        or ('%s/%s/%s'):format(RELEASE_BASE, LLAMA_VERSION, asset)
    local dir = managed_root()
    local archive = vim.fn.stdpath 'cache' .. '/Trans/llama-' .. LLAMA_VERSION .. ext

    vim.fn.mkdir(dir, 'p')
    vim.fn.mkdir(vim.fn.fnamemodify(archive, ':h'), 'p')

    local fetch

    local function extract(retry)
        local cmd
        if ext == '.zip' then
            -- Windows 10+ ships bsdtar, which can unpack zip archives.
            if Trans.system == 'win' then
                cmd = { 'tar', '-xf', archive, '-C', dir }
            else
                cmd = { 'unzip', '-q', '-o', archive, '-d', dir }
            end
        else
            cmd = { 'tar', '-xzf', archive, '-C', dir }
        end

        local job = vim.fn.jobstart(cmd, {
            stdout = '',
            stderr = '',
            on_exit = function(_, code)
                local server = managed_server()
                if code == 0 and server then
                    callback(true)
                    return
                end

                -- A broken or truncated archive is downloaded again once.
                pcall(vim.fn.delete, archive)
                if retry then
                    fetch(false)
                else
                    callback(false, ('解压 llama-server 失败 (exit %d)'):format(code))
                end
            end,
        })

        if job <= 0 then
            callback(false, '无法启动解压命令，请确认已安装 tar/unzip')
        end
    end

    fetch = function(retry)
        notify(('首次使用，正在下载 llama-server %s（约 22MB）...'):format(LLAMA_VERSION), vim.log.levels.INFO)

        local job = vim.fn.jobstart({
            'curl', '-fL',
            '--retry', '3',
            '--retry-delay', '2',
            '--connect-timeout', '15',
            '-o', archive,
            url,
        }, {
            stdout = '',
            stderr = '',
            on_exit = function(_, code)
                if code ~= 0 then
                    pcall(vim.fn.delete, archive)
                    callback(false, ('下载 llama-server 失败 (curl exit %d)\n%s'):format(code, url))
                    return
                end
                notify('llama-server 下载完成，正在解压...', vim.log.levels.INFO)
                extract(retry)
            end,
        })

        if job <= 0 then
            callback(false, '无法启动 curl，请确认已安装 curl')
        end
    end

    local size = vim.fn.getfsize(archive)
    if size and size >= DOWNLOAD_MIN_SIZE then
        extract(true)
    else
        fetch(true)
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

    local lines = { '本地大模型服务无法启动：' }

    if not model then
        lines[#lines + 1] = '  1. 未找到 GGUF 模型，请自行下载后放到：'
        lines[#lines + 1] = '     ' .. default_model_path()
        lines[#lines + 1] = '     或在 Trans.json 中设置 llm.model_path。'
        lines[#lines + 1] = '     模型下载: https://modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF'
    end

    if not server then
        lines[#lines + 1] = '  2. 未找到 llama-server，且自动下载已关闭。'
        lines[#lines + 1] = '     删除 Trans.json 中的 auto_download = false，或设置 llm.server_bin。'
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

    local function fail(message)
        state.starting = false
        if message and message ~= '' then
            notify(message, vim.log.levels.ERROR)
        end
        flush(true) -- still try baidu / youdao fallback
    end

    local function start_server(model, server)
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
            fail(('启动本地模型失败: %s\n日志: %s'):format(tostring(err), log_path))
            return
        end

        local timeout = (tonumber(backend.start_timeout) or 120) * 1000
        local deadline = uv.hrtime() + timeout * 1000000

        local function poll()
            if uv.hrtime() > deadline then
                fail('本地模型启动超时，请查看日志: ' .. log_path)
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
    end

    check_health(health_url, function(ok)
        if ok then
            state.ready = true
            state.starting = false
            flush(true)
            return
        end

        local model = M.find_model(backend.model_path)
        if not model then
            state.starting = false
            notify_missing(nil, true)
            flush(true)
            return
        end

        local server = M.find_server(backend.server_bin)
        if server then
            start_server(model, server)
            return
        end

        if backend.auto_download == false then
            state.starting = false
            notify_missing(model, nil)
            flush(true)
            return
        end

        -- The service is installed on first use; the model stays user-managed.
        download_server(backend, function(downloaded, err)
            if not downloaded then
                fail(err)
                return
            end

            local installed = M.find_server(backend.server_bin)
            if not installed then
                fail('llama-server 下载完成，但没有找到可执行文件')
                return
            end

            notify('llama-server 已安装: ' .. installed, vim.log.levels.INFO)
            start_server(model, installed)
        end)
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
