local node = require 'Trans'.util.node
local it, t, f, co = node.item, node.text, node.format, node.prompt
local interval = (' '):rep(4)


---@class TransHover
---@field offline TransHoverRenderer

---@type TransHoverRenderer
local M = {}

function M.title(hover, result)
    local title = result.title
    if not title then
        hover.buffer:setline(it { result.str, 'TransWord' })
        return
    end
    if type(title) == 'string' then
        hover.buffer:setline(it { title, 'TransWord' })
        return
    end

    local icon  = hover.opts.icon
    local nodes = { it { title.word or result.str, 'TransWord' } }

    local phonetic = title.phonetic
    if type(phonetic) == 'string' and phonetic ~= '' then
        nodes[#nodes + 1] = t {
            it { '[' },
            it { phonetic, 'TransPhonetic' },
            it { ']' },
        }
    end

    -- Oxford / Collins levels only exist for the removed offline dictionary.
    if title.collins then
        nodes[#nodes + 1] = it { icon.star:rep(title.collins), 'TransCollins' }
    end
    if title.oxford then
        nodes[#nodes + 1] = it { title.oxford == 1 and icon.yes or icon.no }
    end

    if #nodes == 1 then
        hover.buffer:setline(nodes[1])
        return
    end

    nodes.width = hover.opts.width
    hover.buffer:setline(f(nodes))
end

function M.tag(hover, result)
    local tag = result.tag
    if not tag then return end

    local buffer = hover.buffer
    buffer:setline(co(hover.opts.icon.tag .. ' 标签'))

    local size = #tag

    for i = 1, size, 3 do
        buffer:setline(it {
            interval .. tag[i] ..
            (tag[i + 1] and interval .. tag[i + 1] ..
            (tag[i + 2] and interval .. tag[i + 2] or '') or ''),
            'TransTag'
        })
    end

    buffer:setline ''
end

function M.exchange(hover, result)
    local exchange = result.exchange
    if not exchange then return end

    local buffer = hover.buffer
    buffer:setline(co(hover.opts.icon.exchange .. ' 词形变化'))

    for description, value in pairs(exchange) do
        buffer:setline(
            it { interval .. description .. interval .. value, 'TransExchange' }
        )
    end

    buffer:setline ''
end

function M.pos(hover, result)
    local pos = result.pos
    if not pos then return end

    local buffer = hover.buffer
    buffer:setline(co(hover.opts.icon.pos .. ' 词性'))

    for description, value in pairs(pos) do
        buffer:setline(
            it { interval .. description .. interval .. value, 'TransPos' }
        )
    end

    buffer:setline ''
end

return M
