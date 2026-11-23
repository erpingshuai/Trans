---@class Trans
---@field install fun(opts?: table) Install llama-server and the GGUF model
return function(opts)
    local Trans = require 'Trans'

    -- Lazy runs `build` before setup(), so opts.dir is needed to find Trans.json.
    -- Fall back to the standard Neovim config directory when it exists.
    local dir = opts and type(opts.dir) == 'string' and vim.fn.expand(opts.dir) or nil
    if dir and dir ~= '' then
        Trans.conf.dir = dir
    elseif vim.fn.filereadable(vim.fn.stdpath 'config' .. '/Trans.json') == 1 then
        Trans.conf.dir = vim.fn.stdpath 'config'
    end

    local backend = Trans.backend.llm
    if opts and type(opts.llm) == 'table' then
        for key, value in pairs(opts.llm) do
            backend[key] = value
        end
    end

    if backend.disable then
        vim.notify('Trans: llm 后端已禁用，跳过安装', vim.log.levels.INFO)
        return
    end

    local host = Trans.server.parse_uri(backend.uri)
    if not host or not Trans.server.is_local(host) or backend.auto_start == false then
        vim.notify('Trans: 使用外部 LLM 服务，无需安装本地模型和服务', vim.log.levels.INFO)
        return
    end

    local server, server_err = Trans.server.find_server(backend.server_bin)
    if not server then
        server, server_err = Trans.server.install_server_sync(backend)
    end

    local model, model_err = Trans.server.find_model(backend.model_path, backend)
    if not model then
        model, model_err = Trans.server.download_model_sync(backend)
    end

    local lines = { 'Trans 本地翻译环境:' }
    if server then
        lines[#lines + 1] = '  ✓ llama-server: ' .. server
    else
        lines[#lines + 1] = '  ✗ llama-server: ' .. (server_err or '未找到')
    end

    if model then
        lines[#lines + 1] = '  ✓ GGUF 模型: ' .. model
    else
        lines[#lines + 1] = '  ✗ GGUF 模型: ' .. (model_err or '未找到')
        lines[#lines + 1] = '    模型路径: ' .. Trans.server.model_target(backend)
    end

    if not (server and model) then
        lines[#lines + 1] = ''
        lines[#lines + 1] = '修复后运行 :TransInstall 重试。'
        lines[#lines + 1] = '本地模型不可用时会自动切换到百度 / 有道。'
    end

    vim.notify(table.concat(lines, '\n'),
        server and model and vim.log.levels.INFO or vim.log.levels.WARN)
end
