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
-   [自动启动本地服务](#自动启动本地服务)
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

-   **首次使用自动启动**：模型和 llama.cpp 由用户自行下载；准备好后按翻译键即可，服务自动启动
-   **本地大模型翻译**：默认使用 `Qwen2.5-0.5B-Instruct`，不需要联网
-   **单词详情**：单个英文单词会额外显示读音（IPA）、词性和英文释义
-   **OpenAI 兼容接口**：自动管理 llama.cpp，也支持 Ollama、LM Studio 等外部服务
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
-   自行下载并放好（**插件不会下载任何文件**）：
    -   模型：[Qwen2.5-0.5B-Instruct GGUF](https://modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF)
    -   [llama.cpp](https://github.com/ggml-org/llama.cpp) 的 `llama-server` 可执行文件
-   模型和二进制齐备后，翻译全程离线
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

模型文件**不包含在仓库中**，插件也不会自动下载。请自行下载并放到下面这个位置
（推荐 ModelScope，国内速度较快）：

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

## 自动启动本地服务

插件**不会下载任何文件**。你需要提前准备好两样东西：

1. 模型文件（见[模型下载](#模型下载)），默认位于：

   ```text
   ~/models/qwen2.5-0.5b-instruct/qwen2.5-0.5b-instruct-q4_k_m.gguf
   ```

   其他位置可在 `Trans.json` 里用 `model_path` 指定。

2. `llama-server` 可执行文件，插件会依次查找：
   - `Trans.json` 中的 `llm.server_bin`
   - `PATH` 中的 `llama-server`
   - `~/.local/share/nvim/Trans/llama/llama-b12559/llama-server`
   - `~/tools/llama/*/llama-server`

准备好之后，第一次执行 `:Translate` / `:TranslateInput` 时，插件会检查
`http://127.0.0.1:18080/health`：已经在运行就直接复用；否则用上面的模型和二进制
在后台启动服务，健康检查通过后再发送翻译请求。

所以装好模型后**不需要手动启动服务**：按翻译快捷键 → 直接用。
启动期间会显示 `Trans:` 通知，运行日志在 `~/.cache/nvim/Trans-llm.log`。
之后 Neovim 重启也无需再管：服务在后台持续运行，下次翻译会直接复用。
如果缺少模型或 `llama-server`，插件不会下载，只会提示你把文件放到哪里。

### 手动准备（可选）

提前下载模型：

```bash
./scripts/download-model.sh
```

提前启动服务：

```bash
./scripts/start-llm.sh
```

脚本会依次查找 `$LLAMA_SERVER`、`PATH` 中的 `llama-server`，以及
`~/tools/llama/*/llama-server`。也可以手动运行：

```bash
llama-server \
  -m ~/models/qwen2.5-0.5b-instruct/qwen2.5-0.5b-instruct-q4_k_m.gguf \
  --host 127.0.0.1 --port 18080 -c 4096
```

默认接口（插件自动管理的 llama.cpp 服务使用 **18080** 端口）：

```text
http://127.0.0.1:18080/v1/chat/completions
```

### 使用外部服务

如果你已经用 Ollama、LM Studio 或其他机器提供了 OpenAI 兼容接口，把
`auto_start` 设为 `false`，`uri` 指向该服务即可。插件不会管理外部服务的生命周期：

```json
{
  "llm": {
    "auto_start": false,
    "uri": "http://127.0.0.1:11434/v1/chat/completions",
    "model": "qwen2.5:0.5b-instruct"
  }
}
```

上面 `11434` 是 Ollama 自身的默认端口；插件自动管理的 llama.cpp 服务固定使用 `18080`。

## 配置

把仓库中的 [`Trans.json.example`](./Trans.json.example) 复制到插件目录，命名为 `Trans.json`：

```bash
cp Trans.json.example Trans.json
```

不写 `Trans.json` 也能直接用：插件内置了本地 Qwen2.5 的默认配置。
需要修改时才创建配置文件，最小配置：

```json
{
  "llm": {
    "uri": "http://127.0.0.1:18080/v1/chat/completions",
    "model": "qwen2.5-0.5b-instruct",
    "auto_start": true,
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
| `auto_start` | `true` | 首次使用时自动启动已安装的本地 llama.cpp（不下载）；用外部服务时设为 `false` |
| `model_path` | `~/models/qwen2.5-0.5b-instruct/qwen2.5-0.5b-instruct-q4_k_m.gguf` | GGUF 模型路径 |
| `server_bin` | 自动查找 | `llama-server` 可执行文件路径 |
| `ctx` | `4096` | llama.cpp 上下文长度 |
| `threads` | `0`（自动） | llama.cpp 线程数 |
| `log_path` | `~/.cache/nvim/Trans-llm.log` | 服务日志路径 |
| `start_timeout` | `120` | 等待服务启动的秒数 |
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

单个英文单词会由大模型再回答一次轻量请求，补读音、词性和英文释义，
显示在悬浮窗的 `TransWord`、`TransPhonetic`、`TransPos`、`TransDefinition` 等行。
短语和句子只显示翻译，不会请求这些信息。

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

会检查 Neovim 版本、`curl`、`Trans.json`、LLM 接口配置，以及模型文件、
`llama-server` 和服务运行状态。

## 常见问题

**翻译超时 / 无法连接本地模型**

先看 `:checkhealth Trans` 里的服务状态。正常情况下服务会在首次翻译时自动启动；
如果用了外部服务，请确认它已运行，并且 `Trans.json` 中的 `uri` 与地址一致：

```bash
curl http://127.0.0.1:18080/v1/models
```

**模型输出多余的解释**

把 `temperature` 设为 `0`，或者自定义 `system_prompt`，明确要求“只输出译文”。

**百度 / 有道没有生效**

检查是否填写了 `app_id` 和 `app_passwd`，以及是否设置了 `"disable": true`。

**第一次翻译比较慢**

首次启动需要加载模型，约 1～3 秒，之后都是秒级响应。
可以提前运行 `scripts/start-llm.sh`，或者把 `frontend.hover.timeout` 调大。
模型请按[模型下载](#模型下载)提前放好，插件不会自动下载。

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
