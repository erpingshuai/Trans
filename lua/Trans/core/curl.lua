---@class TransCurl
local curl = {}

---@class RequestResult
---@field body string
---@field exit integer exit code
---@field error string error message from stderr


---@class TransCurlOptions
---@field query table<string, string> query arguments
---@field body? table|string request body (POST)
---@field output string output file path
---@field header? table<string, string> headers
---@field headers? table<string, string> headers (alias)
---@field timeout? integer timeout in seconds
---@field callback fun(result: RequestResult)
---@field extra? string[] extra curl arguments


---Collect stdout/stderr chunks from a job
---@param target string[]
---@return fun(_, data: string[]?)
local function collector(target)
    return function(_, data)
        if not data then return end
        target[#target + 1] = table.concat(data, '\n')
    end
end


---@param headers table<string, string>?
---@return table<string, string>?
local function normalize_headers(headers)
    if not headers then return nil end

    local normalized = {}
    for k, v in pairs(headers) do
        normalized[k] = v
    end
    return normalized
end


---@async
---Send a GET request use curl
---@param uri string uri for request
---@param opts TransCurlOptions
function curl.get(uri, opts)
    local query    = opts.query
    local output   = opts.output
    local headers  = normalize_headers(opts.header or opts.headers)
    local callback = opts.callback
    local extra    = opts.extra


    -- INFO :Init Curl command with {s}ilent and {G}et
    local cmd  = vim.list_extend({ 'curl', '-GLsS', uri }, extra or {})
    local size = #cmd
    local function add(value)
        size = size + 1
        cmd[size] = value
    end

    -- INFO :Add headers
    if headers then
        for k, v in pairs(headers) do
            add(('-H %q: %q'):format(k, v))
        end
    end

    -- INFO :Add arguments
    if query then
        for k, v in pairs(query) do
            add(('--data-urlencode %q=%q'):format(k, v))
        end
    end

    -- INFO :Store output to file
    if output then
        add(('-o %q'):format(output))
    end

    -- INFO : Start a job
    local stdout, stderr = {}, {}
    local on_exit = function(_, exit)
        callback {
            exit = exit,
            body = table.concat(stdout),
            error = table.concat(stderr),
        }
    end

    -- vim.print(table.concat(cmd, ' '))
    vim.fn.jobstart(table.concat(cmd, ' '), {
        stdin = 'null',
        on_stdout = collector(stdout),
        on_stderr = collector(stderr),
        on_exit = on_exit,
    })
end


---@async
---Send a POST request with a JSON body use curl
---@param uri string uri for request
---@param opts TransCurlOptions
function curl.post(uri, opts)
    local callback = opts.callback
    local headers  = normalize_headers(opts.header or opts.headers) or {}

    local cmd = { 'curl', '-sS', '-X', 'POST', uri }

    if opts.timeout then
        vim.list_extend(cmd, { '--max-time', tostring(opts.timeout) })
    end

    local has_content_type = false
    for k, v in pairs(headers) do
        if k:lower() == 'content-type' then
            has_content_type = true
        end
        vim.list_extend(cmd, { '-H', ('%s: %s'):format(k, v) })
    end

    if not has_content_type then
        vim.list_extend(cmd, { '-H', 'Content-Type: application/json' })
    end

    -- INFO :Read request body from stdin to avoid shell quoting issues
    vim.list_extend(cmd, { '--data-binary', '@-' })

    local stdout, stderr = {}, {}
    local job = vim.fn.jobstart(cmd, {
        stdin = 'pipe',
        on_stdout = collector(stdout),
        on_stderr = collector(stderr),
        on_exit = function(_, exit)
            callback {
                exit = exit,
                body = table.concat(stdout),
                error = table.concat(stderr),
            }
        end,
    })

    if job <= 0 then
        callback {
            exit = job,
            body = '',
            error = 'failed to start curl',
        }
        return
    end

    local body = opts.body
    if type(body) ~= 'string' then
        body = vim.json.encode(body or {})
    end

    pcall(vim.fn.chansend, job, body)
    pcall(vim.fn.chanclose, job, 'stdin')
end


---@class Trans
---@field curl TransCurl
return curl
