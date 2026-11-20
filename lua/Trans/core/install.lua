---@class Trans
---@field install fun() Show local model setup instructions
return function()
    local Trans = require 'Trans'

    vim.notify(table.concat({
        'Trans.nvim 现在使用本地大模型翻译，不再需要下载离线词库。',
        '',
        '模型: Qwen2.5-0.5B-Instruct (GGUF)，模型文件不包含在仓库中',
        '下载脚本: ./scripts/download-model.sh',
        'ModelScope: https://modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF',
        'HuggingFace: https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF',
        '',
        '启动 llama.cpp 服务:',
        '  ./scripts/start-llm.sh',
        '或:',
        '  llama-server -m qwen2.5-0.5b-instruct-q4_k_m.gguf \\',
        '    --host 127.0.0.1 --port 8080 -c 4096',
        '',
        '默认接口: http://127.0.0.1:8080/v1/chat/completions',
        '配置文件: ' .. Trans.conf.dir .. '/Trans.json',
    }, '\n'), vim.log.levels.INFO)
end
