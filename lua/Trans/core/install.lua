---@class Trans
---@field install fun() Show local LLM setup information
return function()
    local Trans = require 'Trans'

    vim.notify(table.concat({
        'Trans 使用本地大模型翻译。',
        '首次翻译时会自动下载并启动 llama-server，',
        'GGUF 模型仍需自行下载（插件不会下载模型）。',
        '',
        '默认接口: http://127.0.0.1:42317/v1/chat/completions',
        '默认模型: ~/models/qwen2.5-0.5b-instruct/qwen2.5-0.5b-instruct-q4_k_m.gguf',
        '配置文件: ' .. Trans.conf.dir .. '/Trans.json',
        '运行状态: :checkhealth Trans',
    }, '\n'), vim.log.levels.INFO)
end
