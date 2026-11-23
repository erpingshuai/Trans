# Trans.nvim

本地大模型驱动的 Neovim 翻译插件。基于原作者 [JuanZoran/Trans.nvim](https://github.com/JuanZoran/Trans.nvim) 的 v2 分支重构，默认使用本地 `Qwen2.5-0.5B-Instruct`，百度 / 有道在线 API 作为可选备用。

插件会在首次安装或首次翻译时自动下载 `llama-server` 和 GGUF 模型。模型默认直接放在插件所在目录（不新建子文件夹），也可以用 `model_dir` 指定其他目录。

## 快速开始

1. 安装插件（lazy.nvim）：

```lua
{
  "erpingshuai/Trans",
  event = "VeryLazy",
  build = function(plugin)
    require("Trans").install(plugin.opts)
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
  build = function(plugin)
    require("Trans").install(plugin.opts)
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

2. 重启 Neovim，按 `<leader>tr` 直接用。

配置了 `build` 时，Lazy 安装 / 更新插件会自动执行 `:TransInstall`。没有执行 `build`（例如本地 `dir` 插件已经装好）也没关系：第一次翻译会检查并按需下载模型和 `llama-server`，然后启动服务完成翻译。也可以随时手动执行：

```vim
:TransInstall
```

打开 Neovim 时不会启动后台服务；服务在第一次翻译时按需启动。

## 模型放哪里

默认模型是 `qwen2.5-0.5b-instruct-q4_k_m.gguf`。`q4_k_m` 质量比 `q3_k_m` 好一些，体积约 485MB；想省空间可以改用 `q3_k_m`（约 322MB），把 `model_file` 改成对应文件名即可。

在 `auto_download_model` 开启且没有设置 `model_dir` 时，自动下载的模型直接放在插件所在目录（不新建子文件夹）：

```text
<plugin_dir>/qwen2.5-0.5b-instruct-q4_k_m.gguf
```

lazy.nvim 管理的插件通常是：

```text
~/.local/share/nvim/lazy/Trans/qwen2.5-0.5b-instruct-q4_k_m.gguf
```

用 `dir = "~/Trans"` 的本地 clone 则是：

```text
~/Trans/qwen2.5-0.5b-instruct-q4_k_m.gguf
```

想放到其他目录，设置 `model_dir`：

```json
{
  "llm": {
    "model_dir": "~/models/trans",
    "model_file": "qwen2.5-0.5b-instruct-q4_k_m.gguf"
  }
}
```

模型查找顺序：

1. `model_path`（最高优先级，直接指定完整文件路径）
2. `model_dir/model_file`
3. 自动下载目录（插件所在目录本身）
4. 旧版默认目录 `~/models/qwen2.5-0.5b-instruct/`
5. `stdpath("data")/Trans/models/`

关闭自动下载（例如离线环境或手动管理模型）：

```json
{
  "llm": {
    "auto_download_model": false
  }
}
```

关闭后默认从 `~/models/qwen2.5-0.5b-instruct/` 查找；也可以用 `model_dir` / `model_path` 指定。

手动下载示例：

```bash
curl -L --fail --retry 5 --retry-delay 3 -C - \
  -o ~/.local/share/nvim/lazy/Trans/qwen2.5-0.5b-instruct-q4_k_m.gguf \
  https://modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/master/qwen2.5-0.5b-instruct-q4_k_m.gguf
```

模型来源：

- ModelScope：<https://modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF>
- Hugging Face：<https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF>

下载地址也可以覆盖（默认使用 ModelScope）：

```json
{
  "llm": {
    "model_url": "https://你的镜像/qwen2.5-0.5b-instruct-q4_k_m.gguf"
  }
}
```

`llama-server` 的查找顺序是：

1. `Trans.json` 里的 `server_bin`
2. 插件自动下载的 `~/.local/share/nvim/Trans/llama/llama-b12559/llama-server`
3. `PATH` 中的 `llama-server`
4. `~/tools/llama/*/llama-server`

都没有时，会在首次安装 / 首次翻译时自动下载并启动。也可以直接指定已有的二进制：

```json
{
  "llm": {
    "server_bin": "/你的目录/llama-server"
  }
}
```

关闭 `llama-server` 自动下载：

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

把仓库里的 `Trans.json.example` 复制为 `Trans.json`。默认放在插件目录（`require("Trans").plugin_dir`）；如果 `setup({ dir = "..." })` 或 Lazy 的 `opts.dir` 设置了其他目录，则放在该目录。下面的例子使用 `stdpath("config")`，Linux 下实际文件是 `~/.config/nvim/Trans.json`。

```bash
cp ~/.local/share/nvim/lazy/Trans/Trans.json.example ~/.config/nvim/Trans.json
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
    "auto_download_model": true,
    "model_file": "qwen2.5-0.5b-instruct-q4_k_m.gguf",
    "temperature": 0,
    "max_tokens": 256,
    "timeout": 60,
    "disable": false
  },
  "baidu": {
    "name": "baidu",
    "app_id": "your_baidu_app_id",
    "app_passwd": "your_baidu_app_passwd",
    "disable": false
  },
  "youdao": {
    "name": "youdao",
    "app_id": "your_youdao_app_id",
    "app_passwd": "your_youdao_app_passwd",
    "disable": false
  }
}
```

示例开启了百度和有道作为备用；不需要时把对应后端的 `disable` 改成 `true`。只有同时填写了 `app_id` 和 `app_passwd`、并且 `disable = false` 的后端才会被启用。

常用字段：

| 字段 | 默认值 | 说明 |
| --- | --- | --- |
| `model_path` | 未设置 | 完整 GGUF 路径，优先级最高 |
| `model_dir` | 自动下载时插件所在目录 `<plugin_dir>`；否则 `~/models/qwen2.5-0.5b-instruct` | 模型目录，支持 `~` |
| `model_file` | `qwen2.5-0.5b-instruct-q4_k_m.gguf` | 模型文件名 |
| `model_url` | ModelScope 对应文件 | 覆盖模型下载地址 |
| `auto_download_model` | `true` | 模型缺失时自动下载 |
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

`opts.llm` 里的配置会覆盖 `Trans.json`，例如：

```lua
opts = {
  dir = vim.fn.stdpath("config"),
  llm = {
    model_dir = vim.fn.expand("~/models/trans"),
    auto_download_model = true,
  },
}
```

## 命令

| 命令 | 说明 |
| --- | --- |
| `:Translate` | 翻译光标下单词或选中文本 |
| `:TranslateInput` | 输入文本翻译 |
| `:TransPlay` | 朗读单词或选中文本 |
| `:TransInstall` | 检查并按需下载模型 / `llama-server` |

setup 配置项（主题、悬浮窗等）见 [`conf.lua`](./lua/Trans/core/conf.lua)：

```lua
require("Trans").setup({
  dir = require("Trans").plugin_dir, -- Trans.json 所在目录
  theme = "default",                 -- default | tokyonight | dracula
  frontend = { hover = { timeout = 15000 } }, -- 避免本地模型较慢时过早降级
})
```

## 服务与排错

- 首次翻译会检查 `http://127.0.0.1:42317/health`；没运行就按需下载模型 / `llama-server`，然后后台启动服务。日志在 `~/.cache/nvim/Trans-llm.log`，服务与 Neovim 分离，重启 Neovim 后继续复用。
- 翻译时按 `llm` → `baidu` → `youdao` 的顺序尝试。大模型服务连接失败、返回错误或返回内容无法解析时，会自动切换到已启用的百度 / 有道后端，不会弹出本地模型错误。
- 如果本地模型不可用，并且百度 / 有道都没有配置，插件会提示在 `Trans.json` 中填写 `app_id` / `app_passwd`。
- `:checkhealth Trans` 查看服务、模型、`llama-server` 状态，并检查百度 / 有道凭据。缺少凭据会显示 `ERROR`；填了凭据但 `disable = true` 会显示 `WARNING`。
- 连不上时先跑 `curl http://127.0.0.1:42317/v1/models` 确认服务已启动。
- 单个英文单词 / 短语会额外显示读音、词性和英文释义；0.5B 模型这部分可能不准确。

依赖：Neovim 0.9+、`curl`、`tar`。模型和 `llama-server` 会在首次安装 / 首次翻译时自动下载。不需要 `sqlite.lua` / ECDICT 词库。

## 致谢

- 原项目：[JuanZoran/Trans.nvim](https://github.com/JuanZoran/Trans.nvim)，原作者 Zoran（[JuanZoran](https://github.com/JuanZoran)），以及[所有贡献者](https://github.com/JuanZoran/Trans.nvim/graphs/contributors)
- 原项目致谢：[ECDICT](https://github.com/skywind3000/ECDICT)、[sqlite.lua](https://github.com/kkharji/sqlite.lua)（当前版本已不再依赖）、[T.vim](https://github.com/sicong-li/T.vim)
- 当前版本使用：[Qwen2.5](https://github.com/QwenLM/Qwen2.5)、[llama.cpp](https://github.com/ggml-org/llama.cpp)、[Neovim](https://github.com/neovim/neovim)

## 许可证

基于原版 Trans.nvim 修改，遵循 MIT 许可证。原始版权归 Zoran 所有，详见 [LICENCE](./LICENCE)。
