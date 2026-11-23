---Auto-start the local OpenAI-compatible llama.cpp server.
---
---The llama-server binary and the GGUF model can both be downloaded on first use.
---Downloads are enabled by default and can be disabled with `auto_download` and
---`auto_download_model` in Trans.json / opts.llm.
local Trans = require 'Trans'

local M = {}

local uv = vim.uv or vim.loop

local LLAMA_VERSION = 'b12559'
local DEFAULT_MODEL_DIR = '~/models/qwen2.5-0.5b-instruct'
local DEFAULT_MODEL_FILE = 'qwen2.5-0.5b-instruct-q4_k_m.gguf'
local MODEL_BASE_URL = 'https://modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/master/'
local RELEASE_BASE = 'https://github.com/ggml-org/llama.cpp/releases/download'
local DOWNLOAD_MIN_SIZE = 1024 * 1024 -- ignore truncated archives
local MODEL_MIN_SIZE = 10 * 1024 * 1024 -- ignore truncated GGUF downloads

local state = {
    starting  = false,
    ready     = false,
    callbacks = {},
    missing_notified = false,
    downloading_model = false,
    model_callbacks = {},
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

---Directory used for the GGUF model (supports `~` and environment variables).
---An explicitly configured model_dir always wins. Otherwise automatically
---downloaded models live directly in the plugin directory (no extra subfolder).
---@param backend table?
---@return string
local function model_dir(backend)
    local configured = expand(backend and backend.model_dir)
    if configured then
        return configured
    end

    if backend and backend.auto_download_model ~= false then
        return Trans.plugin_dir
    end

    return vim.fn.expand(DEFAULT_MODEL_DIR)
end

---GGUF file name inside model_dir.
---@param backend table?
---@return string
local function model_file(backend)
    local file = backend and backend.model_file
    if type(file) == 'string' and file ~= '' then
        return vim.fn.fnamemodify(file, ':t')
    end
    return DEFAULT_MODEL_FILE
end

---Default location: model_dir/model_file.
---@param backend table?
---@return string
local function default_model_path(backend)
    return model_dir(backend) .. '/' .. model_file(backend)
end

---Where a downloaded model should be written. An explicit model_path wins.
---@param backend table
---@return string
function M.model_target(backend)
    return expand(backend.model_path) or default_model_path(backend)
end

---Download URL for the configured model. Any Qwen2.5 GGUF filename works.
---@param backend table
---@return string
function M.model_url(backend)
    if type(backend.model_url) == 'string' and backend.model_url ~= '' then
        return backend.model_url
    end
    return MODEL_BASE_URL .. vim.fn.fnamemodify(M.model_target(backend), ':t')
end

---Whether an online backend (baidu/youdao) is configured as a fallback.
---@return boolean
local function has_online_fallback()
    for _, name in ipairs(Trans.backend.all_name) do
        if name ~= 'llm' then
            return true
        end
    end
    return false
end

---Report local-model problems as info when an online fallback exists.
---@param message string
local function notify_local_failure(message)
    local level = has_online_fallback() and vim.log.levels.INFO or vim.log.levels.ERROR
    notify(message, level)
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
---Priority: explicit model_path > model_dir/model_file > old default > data dir.
---@param configured string?
---@param backend table?
---@return string?
function M.find_model(configured, backend)
    backend = backend or {}

    local candidates = {}
    local explicit = expand(configured) or expand(backend.model_path)
    if explicit then
        candidates[#candidates + 1] = explicit
    end
    candidates[#candidates + 1] = default_model_path(backend)
    -- Backwards compatibility with the old ~/models layout.
    candidates[#candidates + 1] = vim.fn.expand(DEFAULT_MODEL_DIR) .. '/' .. model_file(backend)
    candidates[#candidates + 1] = vim.fn.stdpath 'data' .. '/Trans/models/' .. model_file(backend)

    for _, path in ipairs(candidates) do
        if vim.fn.filereadable(path) == 1 and vim.fn.getfsize(path) > 0 then
            return path
        end
    end
end

---Download and unpack the official llama.cpp release for this platform.
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

---Run a command synchronously and return whether it succeeded.
---@param cmd string[]
---@return boolean
local function run_sync(cmd)
    vim.fn.system(cmd)
    return vim.v.shell_error == 0
end

---Download and unpack llama-server synchronously (used by install / LI build).
---@param backend table
---@return string? server
---@return string? err
function M.install_server_sync(backend)
    local server = M.find_server(backend.server_bin)
    if server then
        return server
    end

    if backend.auto_download == false then
        return nil, 'auto_download = false，且没有找到 llama-server'
    end

    local asset, ext = platform_asset()
    if not asset then
        return nil, '当前系统/架构没有可用的 llama.cpp 预编译包，请手动设置 llm.server_bin'
    end

    local url = backend.server_url
        or ('%s/%s/%s'):format(RELEASE_BASE, LLAMA_VERSION, asset)
    local dir = managed_root()
    local archive = vim.fn.stdpath 'cache' .. '/Trans/llama-' .. LLAMA_VERSION .. ext

    vim.fn.mkdir(dir, 'p')
    vim.fn.mkdir(vim.fn.fnamemodify(archive, ':h'), 'p')

    local size = vim.fn.getfsize(archive)
    if not (size and size >= DOWNLOAD_MIN_SIZE) then
        notify(('首次使用，正在下载 llama-server %s（约 22MB）...'):format(LLAMA_VERSION), vim.log.levels.INFO)
        if not run_sync({
            'curl', '-fL',
            '--retry', '3',
            '--retry-delay', '2',
            '--connect-timeout', '15',
            '-o', archive,
            url,
        }) then
            pcall(vim.fn.delete, archive)
            return nil, ('下载 llama-server 失败 (curl exit %d)\n%s'):format(vim.v.shell_error, url)
        end
    end

    notify('正在解压 llama-server...', vim.log.levels.INFO)
    local cmd
    if ext == '.zip' then
        if Trans.system == 'win' then
            cmd = { 'tar', '-xf', archive, '-C', dir }
        else
            cmd = { 'unzip', '-q', '-o', archive, '-d', dir }
        end
    else
        cmd = { 'tar', '-xzf', archive, '-C', dir }
    end

    if not run_sync(cmd) then
        pcall(vim.fn.delete, archive)
        return nil, ('解压 llama-server 失败 (exit %d)'):format(vim.v.shell_error)
    end

    local installed = managed_server()
    if not installed then
        pcall(vim.fn.delete, archive)
        return nil, 'llama-server 解压完成，但没有找到可执行文件'
    end

    notify('llama-server 已安装: ' .. installed, vim.log.levels.INFO)
    return installed
end

---Download the GGUF model synchronously (used by install / Lazy build).
---@param backend table
---@return string? model
---@return string? err
function M.download_model_sync(backend)
    local existing = M.find_model(backend.model_path, backend)
    if existing then
        return existing
    end

    if backend.auto_download_model == false then
        return nil, 'auto_download_model = false，且没有找到 GGUF 模型'
    end

    local target = M.model_target(backend)
    local part = target .. '.part'
    vim.fn.mkdir(vim.fn.fnamemodify(target, ':h'), 'p')

    notify(('首次使用，正在下载模型 %s（约 300~400MB，请稍候）...')
        :format(vim.fn.fnamemodify(target, ':t')), vim.log.levels.INFO)

    local ok = run_sync({
        'curl', '-fL',
        '--retry', '3',
        '--retry-delay', '2',
        '--connect-timeout', '15',
        '-C', '-',
        '-o', part,
        M.model_url(backend),
    })

    if not ok then
        return nil, ('下载模型失败 (curl exit %d)\n%s\n已保留断点文件: %s')
            :format(vim.v.shell_error, M.model_url(backend), part)
    end

    local size = vim.fn.getfsize(part)
    if not size or size < MODEL_MIN_SIZE then
        return nil, ('模型文件不完整: %s\n可重新执行 :TransInstall 断点续传'):format(part)
    end

    local renamed, err = uv.fs_rename(part, target)
    if not renamed then
        return nil, ('保存模型失败: %s'):format(tostring(err))
    end

    notify('模型下载完成: ' .. target, vim.log.levels.INFO)
    return target
end

---Run queued model-download callbacks.
---@param ok boolean
---@param result string?
local function flush_model(ok, result)
    local callbacks = state.model_callbacks
    state.model_callbacks = {}
    for _, callback in ipairs(callbacks) do
        local called, err = pcall(callback, ok, result)
        if not called then
            notify('内部错误: ' .. tostring(err), vim.log.levels.ERROR)
        end
    end
end

---Ensure the GGUF model exists, downloading it in the background if needed.
---@param backend table
---@param callback fun(ok: boolean, model: string?)
function M.ensure_model(backend, callback)
    state.model_callbacks[#state.model_callbacks + 1] = callback

    local model = M.find_model(backend.model_path, backend)
    if model then
        flush_model(true, model)
        return
    end

    if backend.auto_download_model == false then
        flush_model(false, nil)
        return
    end

    if state.downloading_model then
        return
    end
    state.downloading_model = true

    local target = M.model_target(backend)
    local part = target .. '.part'
    vim.fn.mkdir(vim.fn.fnamemodify(target, ':h'), 'p')

    notify(('首次使用，正在下载模型 %s（约 300~400MB，请稍候）...')
        :format(vim.fn.fnamemodify(target, ':t')), vim.log.levels.INFO)

    local job = vim.fn.jobstart({
        'curl', '-fL',
        '--retry', '3',
        '--retry-delay', '2',
        '--connect-timeout', '15',
        '-C', '-',
        '-o', part,
        M.model_url(backend),
    }, {
        stdout = '',
        stderr = '',
        on_exit = function(_, code)
            state.downloading_model = false

            if code ~= 0 then
                flush_model(false, nil)
                notify(('下载模型失败 (curl exit %d)，将使用在线翻译。\n%s\n已保留断点文件: %s')
                    :format(code, M.model_url(backend), part),
                    has_online_fallback() and vim.log.levels.WARN or vim.log.levels.ERROR)
                return
            end

            local size = vim.fn.getfsize(part)
            if not size or size < MODEL_MIN_SIZE then
                flush_model(false, nil)
                notify('模型文件不完整，可重新执行 :TransInstall 断点续传', vim.log.levels.ERROR)
                return
            end

            local renamed, err = uv.fs_rename(part, target)
            if not renamed then
                flush_model(false, nil)
                notify('保存模型失败: ' .. tostring(err), vim.log.levels.ERROR)
                return
            end

            notify('模型下载完成: ' .. target, vim.log.levels.INFO)
            flush_model(true, target)
        end,
    })

    if job <= 0 then
        state.downloading_model = false
        flush_model(false, nil)
        notify('无法启动 curl，请确认已安装 curl', vim.log.levels.ERROR)
    end
end

---Explain what the user must provide when a local service cannot be started.
---@param backend table
---@param model string?
---@param server string?
local function notify_missing(backend, model, server)
    if state.missing_notified then
        return
    end
    state.missing_notified = true

    local lines = { '本地大模型服务无法启动：' }

    if not model then
        lines[#lines + 1] = '  1. 未找到 GGUF 模型。'
        lines[#lines + 1] = '     模型目录: ' .. model_dir(backend)
        lines[#lines + 1] = '     文件名:   ' .. model_file(backend)
        lines[#lines + 1] = '     可在 Trans.json / opts.llm 中设置 model_dir、model_file，'
        lines[#lines + 1] = '     或设置 auto_download_model = true 自动下载。'
        lines[#lines + 1] = '     模型来源: ' .. MODEL_BASE_URL
    end

    if not server then
        lines[#lines + 1] = '  2. 未找到 llama-server，且自动下载已关闭。'
        lines[#lines + 1] = '     设置 auto_download = true，或设置 llm.server_bin。'
    end

    notify_local_failure(table.concat(lines, '\n'))
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
            notify_local_failure(message)
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

    local function ensure_server(model)
        local server = M.find_server(backend.server_bin)
        if server then
            start_server(model, server)
            return
        end

        if backend.auto_download == false then
            state.starting = false
            notify_missing(backend, model, nil)
            flush(true)
            return
        end

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
    end

    check_health(health_url, function(ok)
        if ok then
            state.ready = true
            state.starting = false
            flush(true)
            return
        end

        local model = M.find_model(backend.model_path, backend)
        if model then
            ensure_server(model)
            return
        end

        if backend.auto_download_model == false then
            state.starting = false
            notify_missing(backend, nil, M.find_server(backend.server_bin))
            flush(true)
            return
        end

        M.ensure_model(backend, function(downloaded, path)
            if not downloaded or not path then
                state.starting = false
                flush(true)
                return
            end
            ensure_server(path)
        end)
    end)
end

---Short status used by :checkhealth.
---@return { running: boolean, uri: string?, model: string?, server: string?, log: string?, model_dir: string?, model_file: string?, auto_download_model: boolean? }
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
        model = M.find_model(backend.model_path, backend),
        model_dir = model_dir(backend),
        model_file = model_file(backend),
        server = M.find_server(backend.server_bin),
        log = expand(backend.log_path) or (vim.fn.stdpath 'cache' .. '/Trans-llm.log'),
        auto_download_model = backend.auto_download_model ~= false,
    }
end

return M
