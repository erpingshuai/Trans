---@class Trans
---@field install fun() Prepare the local model (normally done automatically)
return function()
    local Trans = require 'Trans'

    vim.notify(table.concat({
        'Trans 现在使用本地大模型翻译，不需要离线词库。',
        '首次使用时插件会自动下载模型与 llama.cpp 并启动服务；',
        '也可以手动运行 scripts/download-model.sh 和 scripts/start-llm.sh。',
        '',
        '默认接口: http://127.0.0.1:18080/v1/chat/completions',
        '配置文件: ' .. Trans.conf.dir .. '/Trans.json',
        '运行状态: :checkhealth Trans',
    }, '\n'), vim.log.levels.INFO)

    Trans.server.ensure_started()
end
