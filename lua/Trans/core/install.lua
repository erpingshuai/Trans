---@class Trans
---@field install fun() Prepare the local model (normally done automatically)
return function()
    local Trans = require 'Trans'

    vim.notify(table.concat({
        'Trans 现在使用本地大模型翻译，不需要离线词库。',
        '插件不会下载任何文件：请先自行下载模型并安装 llama.cpp，',
        '之后首次翻译时会自动启动本地服务。下载与目录说明见 README。',
        '',
        '默认接口: http://127.0.0.1:18080/v1/chat/completions',
        '配置文件: ' .. Trans.conf.dir .. '/Trans.json',
        '运行状态: :checkhealth Trans',
    }, '\n'), vim.log.levels.INFO)

    Trans.server.ensure_started()
end
