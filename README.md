# Trans.nvim

> 本地大模型驱动的 Neovim 翻译插件。

`Trans.nvim` 基于原作者 [JuanZoran/Trans.nvim](https://github.com/JuanZoran/Trans.nvim) 的 v2 分支重构。
原来的离线词库 / iciba 后端已经被移除，翻译底层改为
[Qwen2.5-0.5B-Instruct](https://github.com/QwenLM/Qwen2.5)，
通过 OpenAI 兼容的本地 HTTP 接口调用；百度、有道在线 API 作为可选备用后端保留。

> **模型文件不包含在本仓库中。** 模型需要自行下载，详见[模型下载](#模型下载)。

## 目录

-   [特点](#特点)
-   [与原版 Trans.nvim 的区别](#与原版-transnvim-的区别)
-   [依赖](#依赖)
-   [安装](#安装)
-   [模型下载](#模型下载)
-   [启动本地服务](#启动本地服务)
-   [配置](#配置)
-   [命令](#命令)
-   [快捷键](#快捷键)
-   [后端](#后端)
-   [高亮组](#高亮组)
-   [健康检查](#健康检查)
-   [常见问题](#常见问题)
-   [性能参考](#性能参考)
-   [致谢](#致谢)
-   [许可证](#许可证)

## 特点

-   **本地大模型翻译**：默认使用 `Qwen2.5-0.5B-Instruct`，不需要联网
-   **OpenAI 兼容接口**：支持 llama.cpp、Ollama、LM Studio 等本地服务
-   **中英互译**：英文单词 / 句子 → 中文，中文 → 英文
-   **悬浮窗 UI**：沿用 Trans.nvim 的 hover 窗口、动画和自动发音
-   **可选在线后端**：百度、有道 API 作为大模型失败后的备用
-   **纯 Lua 编写**：异步调用 `curl`，不阻塞 Neovim
-   **配置简单**：一个 `Trans.json` 即可

## 与原版 Trans.nvim 的区别

| 项目 | 原版 Trans.nvim v2 | 本项目 |
| --- | --- | --- |
| 默认翻译底层 | ECDICT 离线词库 + 在线 API | 本地 Qwen2.5-0.5B-Instruct |
| 离线词库 / sqlite | 需要 | 已移除 |
| iciba 后端 | 有 | 已移除 |
| 百度 / 有道 | 支持 | 保留，可选备用 |
| Lua 模块 | `require('Trans')` | `require('Trans')`（相同） |
| 配置文件 | `Trans.json` | `Trans.json`（相同） |
| 命令 | `:Translate` / `:TranslateInput` / `:TransPlay` | 相同 |
| 高亮组前缀 | `Trans*` | 相同 |

## 依赖

-   Neovim 0.9+
-   `curl`
-   一个本地大模型服务（推荐 [llama.cpp](https://github.com/ggml-org/llama.cpp)）
-   [Qwen2.5-0.5B-Instruct GGUF](https://modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF) 模型文件
-   可选：自动发音需要的系统 TTS 命令
    -   macOS：`say`
    -   Linux：`festival`
    -   Termux：`termux-api`
    -   Windows：PowerShell

> 不再需要 `sqlite.lua`、`sqlite3`、ECDICT 词库。

## 安装

### lazy.nvim

```lua
{
    "erpingshuai/Trans",
    config = function()
        require("Trans").setup({})

        vim.keymap.set('n', 'mi', '<Cmd>TranslateInput<CR>')
        vim.keymap.set({'n', 'x'}, 'mm', '<Cmd>Translate<CR>')
        vim.keymap.set({'n', 'x'}, 'mk', '<Cmd>TransPlay<CR>')
    end,
}
```

如果使用 `keys` 做惰性加载，可以这样写：

```lua
{
    "erpingshuai/Trans",
    keys = {
        { 'mm', mode = { 'n', 'x' }, '<Cmd>Translate<CR>', desc = 'Trans translate' },
        { 'mk', mode = { 'n', 'x' }, '<Cmd>TransPlay<CR>', desc = 'Trans play' },
        { 'mi', '<Cmd>TranslateInput<CR>', desc = 'Trans input' },
    },
    config = function()
        require("Trans").setup({})
    end,
}
```

### packer.nvim

```lua
use {
    'erpingshuai/Trans',
    config = function()
        require('Trans').setup {}
    end,
}
```

安装示例中的仓库地址为 `erpingshuai/Trans`，也可以换成你自己的 fork。

## 模型下载

模型文件**不包含在仓库中**，请自行下载。推荐使用 ModelScope（国内速度较快）：

```bash
./scripts/download-model.sh
```

默认下载到：

```text
~/models/qwen2.5-0.5b-instruct/qwen2.5-0.5b-instruct-q4_k_m.gguf
```

也可以手动下载：

-   ModelScope（推荐国内使用）：
    <https://modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF>
-   Hugging Face：
    <https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF>
-   Ollama：
    ```bash
    ollama pull qwen2.5:0.5b-instruct
    ```

推荐文件：`qwen2.5-0.5b-instruct-q4_k_m.gguf`（约 469 MB）。

> 也对比过体积相近的 Qwen3-0.6B（Q4_K_M / Q6_K）和 Qwen3.5-0.8B（Q4_K_M）：
> 前者的非思考模式在翻译时容易只输出片段，后者速度慢约一倍且偶有漏译/错译。
> 综合速度和中英互译准确度，当前版本仍使用 Qwen2.5-0.5B-Instruct。

> 模型文件已被 `.gitignore` 忽略（`*.gguf`），不会误提交到仓库。

## 启动本地服务

### llama.cpp

先安装 llama.cpp，任选一种：

```bash
sudo port install llama.cpp   # macOS + MacPorts
brew install llama.cpp        # macOS + Homebrew
```

也可以直接下载官方预编译包（不需要包管理器）：

```bash
# Apple Silicon 用 macos-arm64，Intel 用 macos-x64
mkdir -p ~/tools/llama && cd ~/tools/llama
curl -L -o llama.tar.gz \
  https://github.com/ggml-org/llama.cpp/releases/latest/download/llama-b12559-bin-macos-x64.tar.gz
tar xzf llama.tar.gz
```

> 预编译包的具体文件名会随版本变化，请到
> <https://github.com/ggml-org/llama.cpp/releases> 查看最新版本。

然后启动：

```bash
./scripts/start-llm.sh
```

脚本会依次查找 `$LLAMA_SERVER`、`PATH` 中的 `llama-server`，以及
`~/tools/llama/*/llama-server`。

或者手动启动：

```bash
llama-server \
  -m ~/models/qwen2.5-0.5b-instruct/qwen2.5-0.5b-instruct-q4_k_m.gguf \
  --host 127.0.0.1 --port 18080 -c 4096
```

默认接口：

```text
http://127.0.0.1:18080/v1/chat/completions
```

### Ollama

```bash
ollama pull qwen2.5:0.5b-instruct
ollama serve
```

然后在 `Trans.json` 中使用：

```json
{
  "llm": {
    "uri": "http://127.0.0.1:11434/v1/chat/completions",
    "model": "qwen2.5:0.5b-instruct"
  }
}
```

## 配置

把仓库中的 [`Trans.json.example`](./Trans.json.example) 复制到插件目录，命名为 `Trans.json`：

```bash
cp Trans.json.example Trans.json
```

最小配置：

```json
{
  "llm": {
    "uri": "http://127.0.0.1:18080/v1/chat/completions",
    "model": "qwen2.5-0.5b-instruct",
    "temperature": 0,
    "max_tokens": 256,
    "timeout": 60
  }
}
```

### LLM 配置项

| 字段 | 默认值 | 说明 |
| --- | --- | --- |
| `uri` | `http://127.0.0.1:18080/v1/chat/completions` | OpenAI 兼容接口地址 |
| `model` | `qwen2.5-0.5b-instruct` | 模型名；Ollama 用 `qwen2.5:0.5b-instruct` |
| `temperature` | `0` | 0 最稳定，避免小模型输出半中半英 |
| `max_tokens` | `256` | 最大输出 token 数 |
| `timeout` | `60` | curl 超时（秒） |
| `api_key` | 无 | 需要鉴权的接口才填写 |
| `system_prompt` | 内置翻译提示词 | 支持 `{{from}}` / `{{to}}` 占位符 |
| `disable` | `false` | 设为 `true` 可禁用该后端 |

### 百度 / 有道

填写 `app_id` 和 `app_passwd` 后，百度 / 有道才会启用，并作为大模型失败后的备用：

```json
{
  "baidu": {
    "app_id": "你的百度 app_id",
    "app_passwd": "你的百度密钥"
  },
  "youdao": {
    "app_id": "你的有道 app_id",
    "app_passwd": "你的有道密钥"
  }
}
```

不使用时设置 `"disable": true`，或者直接不写。

### setup 配置

```lua
require('Trans').setup {
    -- 配置文件目录，默认是插件目录
    dir = require('Trans').plugin_dir,

    -- 主题：default | tokyonight | dracula
    theme = 'default',

    -- 前端设置
    frontend = {
        hover = {
            width = 37,
            height = 27,
            timeout = 8000, -- 等待本地模型的时间（毫秒）
        },
    },
}
```

完整默认配置见 [`lua/Trans/core/conf.lua`](./lua/Trans/core/conf.lua)。

## 命令

| 命令 | 说明 |
| --- | --- |
| `:Translate` | 翻译光标下单词或选中文本 |
| `:TranslateInput` | 输入一段文本进行翻译 |
| `:TransPlay` | 朗读光标下单词或选中文本 |

## 快捷键

```lua
vim.keymap.set('n', 'mi', '<Cmd>TranslateInput<CR>')
vim.keymap.set({'n', 'x'}, 'mm', '<Cmd>Translate<CR>')
vim.keymap.set({'n', 'x'}, 'mk', '<Cmd>TransPlay<CR>')
```

悬浮窗快捷键：

```lua
require('Trans').setup {
    frontend = {
        hover = {
            keymaps = {
                -- pageup       = '<C-u>',
                -- pagedown     = '<C-d>',
                -- pin          = '<leader>[',
                -- close        = '<leader>]',
                -- toggle_entry = '<leader>;',
            },
        },
    },
}
```

## 后端

| 后端 | 名称 | 默认 | 说明 |
| --- | --- | --- | --- |
| 本地大模型 | `llm` | 启用 | OpenAI 兼容接口 |
| 百度 | `baidu` | 配置密钥后启用 | 备用 |
| 有道 | `youdao` | 配置密钥后启用 | 备用 |

翻译时会按 `llm` → `baidu` → `youdao` 的顺序尝试。

## 高亮组

所有高亮组以 `Trans` 开头，例如：

-   `TransWord`
-   `TransTranslation`
-   `TransDefinition`
-   `TransTitle`
-   `TransBorder`
-   `TransFailed`
-   `TransWaitting`

完整配色见 [`lua/Trans/style/theme.lua`](./lua/Trans/style/theme.lua)。

## 健康检查

```vim
:checkhealth Trans
```

会检查 Neovim 版本、`curl`、`Trans.json` 以及当前 LLM 接口配置。

## 常见问题

**翻译超时 / 无法连接本地模型**

确认本地服务已经启动，并且 `Trans.json` 中的 `uri` 与启动地址一致：

```bash
curl http://127.0.0.1:18080/v1/models
```

**模型输出多余的解释**

把 `temperature` 设为 `0`，或者自定义 `system_prompt`，明确要求“只输出译文”。

**百度 / 有道没有生效**

检查是否填写了 `app_id` 和 `app_passwd`，以及是否设置了 `"disable": true`。

**第一次翻译比较慢**

本地模型首次加载需要时间。可以提前启动服务，或者把 `frontend.hover.timeout` 调大。

**模型文件太大，不想提交到 Git**

模型文件默认放在 `~/models/`，并且 `.gitignore` 已忽略 `*.gguf`、`*.safetensors`、`*.bin` 和 `models/`。

## 性能参考

以下数据来自 Intel i7-9750H（6 线程 CPU 推理，`Q4_K_M` 量化）：

| 场景 | 耗时 |
| --- | --- |
| 单词（如 `resilient`、`deadlock`） | 约 0.1 秒 |
| 短语（如 `race condition`、`pull request`） | 约 0.1 秒 |
| 整句（20～30 个汉字 / 10～15 个英文单词） | 约 0.3～0.5 秒 |
| 服务冷启动后第一次翻译 | 约 0.7～1.3 秒 |
| 内存占用 | 约 630 MB |

实际速度取决于 CPU / GPU 性能，使用 Metal、CUDA 等加速会更快。

翻译质量方面：

-   常见单词、技术术语和固定搭配表现不错，例如 `race condition → 竞态条件`、`deadlock → 死锁`、`pull request → 拉取请求`、`画蛇添足 → gild the lily`
-   日常句子可以稳定翻译，`temperature = 0` 时输出基本确定
-   0.5B 模型能力有限，长段落、专业领域文本或需要上下文的歧义词仍可能出错
-   内置了少量中英技术词 / 习语示例，可按需修改 `lua/Trans/backend/llm.lua` 中的 `EXAMPLES`

## 致谢

-   原项目：[JuanZoran/Trans.nvim](https://github.com/JuanZoran/Trans.nvim)
-   原作者：Zoran（[JuanZoran](https://github.com/JuanZoran)）
-   [Trans.nvim 的所有贡献者](https://github.com/JuanZoran/Trans.nvim/graphs/contributors)
-   原项目致谢：
    -   [ECDICT](https://github.com/skywind3000/ECDICT)（当前版本已不再依赖）
    -   [sqlite.lua](https://github.com/kkharji/sqlite.lua)（当前版本已不再依赖）
    -   [T.vim](https://github.com/sicong-li/T.vim) 灵感来源
-   当前版本使用：
    -   [Qwen2.5](https://github.com/QwenLM/Qwen2.5)
    -   [llama.cpp](https://github.com/ggml-org/llama.cpp)
    -   [Neovim](https://github.com/neovim/neovim)

## 许可证

本项目基于原版 Trans.nvim 修改，遵循 MIT 许可证。
原始版权归 Zoran 所有，详见 [LICENCE](./LICENCE)。
