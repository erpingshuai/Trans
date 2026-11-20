---Local LLM backend (OpenAI compatible chat completions).
---Designed for Qwen2.5-0.5B-Instruct served by llama.cpp / Ollama / LM Studio.
---@class LLM: TransOnlineBackend
---@field uri string OpenAI compatible chat completions endpoint
---@field model string model name or GGUF alias
---@field api_key? string optional bearer token
---@field temperature? number
---@field max_tokens? integer
---@field timeout? integer curl timeout in seconds
---@field system_prompt? string prompt template, supports {{from}} and {{to}}
---@field auto_start? boolean download/start the local llama.cpp server on first use
---@field model_path? string path to the GGUF file
---@field server_bin? string path to the llama-server binary
---@field ctx? integer llama.cpp context size
---@field threads? integer llama.cpp threads (0 = auto)
---@field log_path? string llama.cpp log file
---@field start_timeout? integer seconds to wait for the server to become healthy
---@field disable? boolean
local M = {
    uri          = 'http://127.0.0.1:18080/v1/chat/completions',
    model        = 'qwen2.5-0.5b-instruct',
    -- 0 keeps small models deterministic and avoids half-translated output
    temperature  = 0,
    max_tokens   = 256,
    timeout      = 60,
    name         = 'llm',
    name_zh      = '大模型',
    method       = 'post',
    -- First-use experience: download and start the local model automatically.
    auto_start   = true,
    ctx          = 4096,
    threads      = 0,
    start_timeout = 120,
}

local Trans = require 'Trans'

local LANGUAGES = {
    en = 'English',
    zh = 'Simplified Chinese',
}

local DEFAULT_PROMPT = table.concat({
    'You are a professional translation engine.',
    'Translate the text sent by the user from {{from}} to {{to}}.',
    'Output only the translated text.',
    'Never add explanations, notes, pinyin, the original text, or quotation marks.',
    'If the input is a single word, output only its most common translation.',
    'Translate idioms, phrases and technical terms by their actual meaning in context.',
    'The output must be in {{to}}; never repeat the input unchanged.',
}, ' ')

---Few-shot examples help the 0.5B model with technical terms and idioms.
---Only short words/phrases are used, sentence examples make the model copy the input.
local EXAMPLES = {
    ['en>zh'] = {
        'race condition -> 竞态条件',
        'deadlock -> 死锁',
        'garbage collection -> 垃圾回收',
        'pull request -> 拉取请求',
        'break a leg -> 祝你好运',
        'robust -> 健壮的',
    },
    ['zh>en'] = {
        '死锁 -> deadlock',
        '竞态条件 -> race condition',
        '画蛇添足 -> gild the lily',
        '缓存 -> cache',
        '重构 -> refactor',
        '健壮性 -> robustness',
    },
}

---Build system prompt for the current request
---@param data TransData
---@return string
local function build_prompt(data)
    local from = LANGUAGES[data.from] or data.from
    local to   = LANGUAGES[data.to] or data.to
    local tpl  = M.system_prompt or DEFAULT_PROMPT
    local prompt = (tpl:gsub('{{from}}', from):gsub('{{to}}', to))

    if not M.system_prompt then
        local examples = EXAMPLES[data.from .. '>' .. data.to]
        if examples then
            prompt = prompt .. '\n\nExamples:\n' .. table.concat(examples, '\n')
        end
    end

    return prompt
end

---Get request body for an OpenAI compatible chat completion
---@param data TransData
---@return table
function M.get_query(data)
    return {
        model       = M.model,
        messages    = {
            {
                role    = 'system',
                content = build_prompt(data),
            },
            {
                role    = 'user',
                content = data.str,
            },
        },
        temperature = M.temperature or 0,
        max_tokens  = M.max_tokens or 256,
        stream      = false,
    }
end

---@param data TransData
---@return table<string, string>
function M.header(data)
    local header = {
        ['Content-Type'] = 'application/json',
    }

    if M.api_key and M.api_key ~= '' then
        header['Authorization'] = 'Bearer ' .. M.api_key
    end

    return header
end

---Remove common noise produced by small models
---@param content string
---@return string
local function clean(content)
    content = content:gsub('\r\n', '\n')
    content = content:gsub('^%s+', ''):gsub('%s+$', '')
    content = content:gsub('^```[%w_%-]*%s*\n?', ''):gsub('\n?```$', '')
    content = content:gsub('^["“”\'](.*)["“”\']$', '%1')
    content = content:gsub('^%s+', ''):gsub('%s+$', '')
    return content
end

---Extract the assistant message from common OpenAI/Ollama response shapes
---@param body table
---@return string?
local function get_content(body)
    local choice = body.choices and body.choices[1]
    local content =
        (choice and choice.message and choice.message.content) or
        (choice and choice.text) or
        (body.message and body.message.content) or -- Ollama /api/chat
        body.response or -- Ollama /api/generate
        body.content

    if type(content) == 'string' then
        return content
    end
end

---@param body table
---@param data TransData
---@return TransResult|false
function M.formatter(body, data)
    if body.error then
        return false
    end

    local content = get_content(body)
    if not content then
        return false
    end

    content = clean(content)
    if content == '' then
        return false
    end

    local lines = {}
    for line in content:gmatch('[^\n]+') do
        line = line:gsub('^%s+', ''):gsub('%s+$', '')
        if line ~= '' then
            lines[#lines + 1] = line
        end
    end

    if #lines == 0 then
        return false
    end

    return {
        str = data.str,
        [data.from == 'en' and 'translation' or 'definition'] = lines,
    }
end

---Report request/response errors in a human readable way
---@param body table?
---@param output RequestResult?
function M.debug(body, output)
    if body and body.error then
        local err = body.error
        local message = type(err) == 'table' and (err.message or err.type) or tostring(err)
        vim.notify('大模型翻译失败: ' .. message, vim.log.levels.ERROR)
        return
    end

    if output and output.exit ~= nil and output.exit ~= 0 then
        local detail = output.error and output.error ~= '' and (': ' .. output.error) or ''
        vim.notify(
            ('无法连接本地大模型服务 (curl exit %s)%s\n请确认服务已启动: %s'):format(
                tostring(output.exit),
                detail,
                M.uri
            ),
            vim.log.levels.ERROR
        )
        return
    end

    vim.notify('大模型返回了无法解析的内容', vim.log.levels.ERROR)
end

---@class TransBackend
---@field llm LLM
return M
