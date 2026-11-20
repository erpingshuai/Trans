# Trans.nvim

本地大模型驱动的 Neovim 翻译插件。基于原作者 [JuanZoran/Trans.nvim](https://github.com/JuanZoran/Trans.nvim) 的 v2 分支重构，默认使用本地 `Qwen2.5-0.5B-Instruct`，百度 / 有道在线 API 作为可选备用。模型文件不在仓库里，需要自行下载。

## 快速开始

1. 安装插件（lazy.nvim）：

```lua
{
  "erpingshuai/Trans",
  keys = {
    { "<leader>tr", "<Cmd>Translate<CR>", mode = { "n", "x" }, desc = "Translate" },
    { "<leader>ti", "<Cmd>TranslateInput<CR>", desc = "Translate input" },
    { "<leader>tp", "<Cmd>TransPlay<CR>", mode = { "n", "x" }, desc = "Trans play" },
  },
}
```

2. 下载模型并放到指定位置（见下一节），同时准备 `llama-server`。
3. 重启 Neovim，按 `<leader>tr` 直接用。

**服务会在首次翻译时自动启动，不需要手动启动、不需要手动下载。**

## 模型放哪里

默认路径：

```text
~/models/qwen2.5-0.5b-instruct/qwen2.5-0.5b-instruct-q4_k_m.gguf
```

下载脚本（下载到上面的默认路径）：

```bash
./scripts/download-model.sh
```

也可以手动下载 `qwen2.5-0.5b-instruct-q4_k_m.gguf`（约 469 MB）：

- ModelScope：<https://modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF>
- Hugging Face：<https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF>

**放到其他位置**时，在 `Trans.json` 里配置 `model_path`：

```json
{
  "llm": {
    "model_path": "/你的目录/qwen2.5-0.5b-instruct-q4_k_m.gguf"
  }
}
```

`llama-server` 需要能被找到：`PATH` 中的 `llama-server`、`~/tools/llama/*/llama-server` 或 `~/.local/share/nvim/Trans/llama/llama-b12559/llama-server`。不在这些位置时用 `server_bin` 指定：

```json
{
  "llm": {
    "server_bin": "/你的目录/llama-server"
  }
}
```

## 配置文件

把仓库里的 `Trans.json.example` 复制为 `Trans.json`，放在插件目录（默认）。也可以通过 `setup({ dir = "..." })` 改目录。**不写 `Trans.json` 也能直接用**，插件有内置默认配置。

完整示例（按需修改）：

```json
{
  "llm": {
    "uri": "http://127.0.0.1:18080/v1/chat/completions",
    "model": "qwen2.5-0.5b-instruct",
    "auto_start": true,
    "model_path": "~/models/qwen2.5-0.5b-instruct/qwen2.5-0.5b-instruct-q4_k_m.gguf",
    "server_bin": "",
    "temperature": 0,
    "max_tokens": 256,
    "timeout": 60
  },
  "baidu": { "app_id": "", "app_passwd": "", "disable": true },
  "youdao": { "app_id": "", "app_passwd": "", "disable": true }
}
```

常用字段：

| 字段 | 默认值 | 说明 |
| --- | --- | --- |
| `model_path` | `~/models/qwen2.5-0.5b-instruct/qwen2.5-0.5b-instruct-q4_k_m.gguf` | GGUF 模型路径 |
| `server_bin` | 自动查找 | `llama-server` 路径 |
| `uri` | `http://127.0.0.1:18080/v1/chat/completions` | OpenAI 兼容接口 |
| `auto_start` | `true` | 首次翻译时自动启动本地服务 |
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
  frontend = { hover = { timeout = 8000 } },
})
```

## 服务与排错

- 首次翻译检查 `http://127.0.0.1:18080/health`，没运行就后台启动；日志在 `~/.cache/nvim/Trans-llm.log`。服务与 Neovim 分离，重启 Neovim 后继续复用。
- `:checkhealth Trans` 查看服务、模型、`llama-server` 状态。
- 连不上时先跑 `curl http://127.0.0.1:18080/v1/models` 确认服务已启动。
- 单个英文单词 / 短语会额外显示读音、词性和英文释义；0.5B 模型这部分可能不准确。

依赖：Neovim 0.9+、`curl`、模型文件、`llama-server`。不需要 `sqlite.lua` / ECDICT 词库。

## 致谢

- 原项目：[JuanZoran/Trans.nvim](https://github.com/JuanZoran/Trans.nvim)，原作者 Zoran（[JuanZoran](https://github.com/JuanZoran)），以及[所有贡献者](https://github.com/JuanZoran/Trans.nvim/graphs/contributors)
- 原项目致谢：[ECDICT](https://github.com/skywind3000/ECDICT)、[sqlite.lua](https://github.com/kkharji/sqlite.lua)（当前版本已不再依赖）、[T.vim](https://github.com/sicong-li/T.vim)
- 当前版本使用：[Qwen2.5](https://github.com/QwenLM/Qwen2.5)、[llama.cpp](https://github.com/ggml-org/llama.cpp)、[Neovim](https://github.com/neovim/neovim)

## 许可证

基于原版 Trans.nvim 修改，遵循 MIT 许可证。原始版权归 Zoran 所有，详见 [LICENCE](./LICENCE)。
