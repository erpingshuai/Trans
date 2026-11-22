# Trans.nvim

本地大模型驱动的 Neovim 翻译插件。基于原作者 [JuanZoran/Trans.nvim](https://github.com/JuanZoran/Trans.nvim) 的 v2 分支重构，默认使用本地 `Qwen2.5-0.5B-Instruct`，百度 / 有道在线 API 作为可选备用。模型文件不在仓库里，需要自行下载。

## 快速开始

1. 安装插件（lazy.nvim）：

```lua
{
  "erpingshuai/Trans",
  event = "VeryLazy",
  build = function()
    require("Trans").install()
  end,
  keys = {
    { "<leader>tr", "<Cmd>Translate<CR>", mode = { "n", "x" }, desc = "Translate" },
    { "<leader>ti", "<Cmd>TranslateInput<CR>", desc = "Translate input" },
    { "<leader>tp", "<Cmd>TransPlay<CR>", mode = { "n", "x" }, desc = "Trans play" },
  },
  opts = {
    dir = vim.fn.stdpath("config"),
    frontend = {
      hover = { timeout = 15000 },
    },
  },
}
```

这样 `Trans.json` 会放在 `vim.fn.stdpath("config")` 目录下（Linux 通常是 `~/.config/nvim/Trans.json`）。

如果使用本仓库的本地 clone（例如 `~/Trans`），把 `dir` 指向它，并用 `opts.dir` 指定 `Trans.json` 所在目录：

```lua
{
  "erpingshuai/Trans",
  dir = vim.fn.expand("~/Trans"),
  event = "VeryLazy",
  build = function()
    require("Trans").install()
  end,
  keys = {
    { "<leader>tr", "<Cmd>Translate<CR>", mode = { "n", "x" }, desc = "Translate" },
    { "<leader>ti", "<Cmd>TranslateInput<CR>", desc = "Translate input" },
    { "<leader>tp", "<Cmd>TransPlay<CR>", mode = { "n", "x" }, desc = "Trans play" },
  },
  opts = {
    dir = vim.fn.stdpath("config"),
    frontend = {
      hover = { timeout = 15000 },
    },
  },
}
```

2. 下载模型并放到指定位置（见下一节）。`llama-server` 不需要手动安装。
3. 重启 Neovim，按 `<leader>tr` 直接用。

打开 Neovim 时不会启动后台服务；第一次执行翻译时才会检查模型和 `llama-server`。模型必须由用户自行准备；模型存在时，缺失的 `llama-server` 会自动下载，然后启动服务并完成翻译。

## 模型放哪里

模型由用户自行准备，插件只负责下载和启动 `llama-server`。

插件内置的默认路径（`q4_k_m`）：

```text
~/models/qwen2.5-0.5b-instruct/qwen2.5-0.5b-instruct-q4_k_m.gguf
```

`Trans.json.example` 使用的是 `q3_k_m`：

```text
~/models/qwen2.5-0.5b-instruct-q3_k_m.gguf
```

用哪个量化版本都可以，关键是 `Trans.json` 里的 `model_path` 指向实际文件：

```json
{
  "llm": {
    "model_path": "~/models/qwen2.5-0.5b-instruct-q3_k_m.gguf"
  }
}
```

下载脚本会下载 `q4_k_m` 到内置默认路径：

```bash
./scripts/download-model.sh
```

也可以手动下载：

- ModelScope：<https://modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF>
- Hugging Face：<https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF>

例如手动下载示例配置使用的 `q3_k_m`：

```bash
curl -L --fail --retry 5 --retry-delay 3 -C - \
  -o ~/models/qwen2.5-0.5b-instruct-q3_k_m.gguf \
  https://modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/master/qwen2.5-0.5b-instruct-q3_k_m.gguf
```

`llama-server` 的查找顺序是：

1. `Trans.json` 里的 `server_bin`
2. 插件自动下载的 `~/.local/share/nvim/Trans/llama/llama-b12559/llama-server`
3. `PATH` 中的 `llama-server`
4. `~/tools/llama/*/llama-server`

都没有时，会在首次翻译时自动下载并启动。也可以直接指定已有的二进制：

```json
{
  "llm": {
    "server_bin": "/你的目录/llama-server"
  }
}
```

关闭自动下载（例如离线环境）：

```json
{
  "llm": {
    "auto_download": false
  }
}
```

下载地址也可以覆盖（默认使用 GitHub Releases）：

```json
{
  "llm": {
    "server_url": "https://你的镜像/llama-b12559-bin-ubuntu-x64.tar.gz"
  }
}
```

## 配置文件

把仓库里的 `Trans.json.example` 复制为 `Trans.json`。默认放在插件目录（`require("Trans").plugin_dir`）；如果 `setup({ dir = "..." })` 设置了其他目录，则放在该目录。本仓库的 Neovim 配置使用 `vim.fn.stdpath("config")`，所以实际文件是 `stdpath("config")/Trans.json`（Linux 下为 `~/.config/nvim/Trans.json`）。

```bash
cp ~/Trans/Trans.json.example ~/.config/nvim/Trans.json
```

**不写 `Trans.json` 也能直接用**，插件有内置默认配置。

完整示例（按需修改）：

```json
{
  "llm": {
    "name": "llm",
    "uri": "http://127.0.0.1:42317/v1/chat/completions",
    "model": "qwen2.5-0.5b-instruct",
    "auto_start": true,
    "auto_download": true,
    "model_path": "~/models/qwen2.5-0.5b-instruct-q3_k_m.gguf",
    "temperature": 0,
    "max_tokens": 256,
    "timeout": 60,
    "disable": false
  },
  "baidu": {
    "name": "baidu",
    "app_id": "your_baidu_app_id",
    "app_passwd": "your_baidu_app_passwd",
    "disable": true
  },
  "youdao": {
    "name": "youdao",
    "app_id": "your_youdao_app_id",
    "app_passwd": "your_youdao_app_passwd",
    "disable": true
  }
}
```

示例默认关闭百度和有道。需要备用后端时，填入对应的 `app_id` / `app_passwd`，并把 `disable` 改为 `false`。

常用字段：

| 字段 | 默认值 | 说明 |
| --- | --- | --- |
| `model_path` | `~/models/qwen2.5-0.5b-instruct/qwen2.5-0.5b-instruct-q4_k_m.gguf` | GGUF 模型路径；示例使用 `q3_k_m`，按实际文件修改 |
| `server_bin` | 未设置时自动查找 | `llama-server` 路径 |
| `server_url` | GitHub Releases | 覆盖 `llama-server` 下载地址 |
| `uri` | `http://127.0.0.1:42317/v1/chat/completions` | OpenAI 兼容接口 |
| `auto_start` | `true` | 首次翻译时自动启动本地服务 |
| `auto_download` | `true` | `llama-server` 缺失时自动下载 |
| `model` | `qwen2.5-0.5b-instruct` | 模型名；Ollama 用 `qwen2.5:0.5b-instruct` |
| `temperature` | `0` | 0 最稳定 |
| `system_prompt` | 内置 | 支持 `{{from}}` / `{{to}}` |
| `disable` | `false` | 禁用该后端 |

其他字段（`ctx`、`threads`、`log_path`、`start_timeout`、`api_key`）见 [`llm.lua`](./lua/Trans/backend/llm.lua)。

用 Ollama / LM Studio / 远程服务时，设 `"auto_start": false`，并把 `uri` 指向对应地址；插件不会管理这类外部服务。

## 命令

| 命令 | 说明 |
| --- | --- |
| `:Translate` | 翻译光标下单词或选中文本 |
| `:TranslateInput` | 输入文本翻译 |
| `:TransPlay` | 朗读单词或选中文本 |

setup 配置项（主题、悬浮窗等）见 [`conf.lua`](./lua/Trans/core/conf.lua)：

```lua
require("Trans").setup({
  dir = require("Trans").plugin_dir, -- Trans.json 所在目录
  theme = "default",                 -- default | tokyonight | dracula
  frontend = { hover = { timeout = 15000 } }, -- 避免本地模型较慢时过早降级
})
```

## 服务与排错

- 模型配置好后，首次翻译会检查 `http://127.0.0.1:42317/health`；没运行就自动下载并后台启动，不需要手动运行 `scripts/start-llm.sh`。日志在 `~/.cache/nvim/Trans-llm.log`，服务与 Neovim 分离，重启 Neovim 后继续复用。
- 翻译时按 `llm` → `baidu` → `youdao` 的顺序尝试。大模型服务连接失败、返回错误或返回内容无法解析时，会自动切换到已启用的百度 / 有道后端。
- 百度 / 有道需要填入 `app_id`、`app_passwd`，并把 `disable` 设为 `false` 才会启用。全部后端都失败时显示失败提示。
- `:checkhealth Trans` 查看服务、模型、`llama-server` 状态。
- 连不上时先跑 `curl http://127.0.0.1:42317/v1/models` 确认服务已启动。
- 单个英文单词 / 短语会额外显示读音、词性和英文释义；0.5B 模型这部分可能不准确。

依赖：Neovim 0.9+、`curl`、模型文件。`llama-server` 会在首次使用时自动下载。不需要 `sqlite.lua` / ECDICT 词库。

## 致谢

- 原项目：[JuanZoran/Trans.nvim](https://github.com/JuanZoran/Trans.nvim)，原作者 Zoran（[JuanZoran](https://github.com/JuanZoran)），以及[所有贡献者](https://github.com/JuanZoran/Trans.nvim/graphs/contributors)
- 原项目致谢：[ECDICT](https://github.com/skywind3000/ECDICT)、[sqlite.lua](https://github.com/kkharji/sqlite.lua)（当前版本已不再依赖）、[T.vim](https://github.com/sicong-li/T.vim)
- 当前版本使用：[Qwen2.5](https://github.com/QwenLM/Qwen2.5)、[llama.cpp](https://github.com/ggml-org/llama.cpp)、[Neovim](https://github.com/neovim/neovim)

## 许可证

基于原版 Trans.nvim 修改，遵循 MIT 许可证。原始版权归 Zoran 所有，详见 [LICENCE](./LICENCE)。
