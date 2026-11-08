// 由上游 standard.patch.yml 生成「标·准· 模式」预设声明。
//
// 目的：保证除 persona 行之外，plugins 列表与当前宿主的标准模式**逐字一致**；
// 上游升级（增删插件行、改 config）后重跑本脚本即可，不必手工对照。
//
// 用法：
//   node mods/agent-preset-standard-assistant/tools/gen-patch.mjs <standard.patch.yml 路径>
// 默认读 tmp/standard-022.patch.yml；从 app.asar 取上游文件的方法见 README「升级」一节。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(HERE, '..', 'standard-assistant.patch.yml');
const SRC = process.argv[2] || path.join(HERE, '..', '..', '..', 'tmp', 'standard-022.patch.yml');

const HEADER = `# 标·准· 模式（agent preset id: standard-assistant）—— 由「标准模式」派生。
#
# 本文件由 tools/gen-patch.mjs 从上游 standard.patch.yml 生成，请勿手改；
# 上游升级后重跑生成脚本（见 README「升级」）。
#
# 与标准模式的唯一差别：系统提示词的**第一项**换成
#   deployment:persona-prefix = "You are a helpful software engineer assistant."
# 其余提示词段与工具行与标准模式逐字一致（本文件即由 standard.patch.yml 生成，
# 去掉标准自己的 persona 行、换成 persona-prefix-first 行）。
#
# 为什么需要一个小插件：内置 persona 段（@deepseek-ai/dsh-persona）的 order 固定为 0，
# 而 harness 身份段 harness:identity 的 order 是 -1000，所以只要还用内置 persona，
# 身份段就一定会排在它前面。persona-prefix-first.mjs 用同名遮蔽（scoped section
# 覆盖 global 同名段）把 deployment:persona-prefix 注册到 order -2000，
# 从而成为整份系统提示词的第一项，其余段保持标准模式的原始顺序。
#
# 安装方式见同目录 README.md / install.ps1。

`;

let text = fs.readFileSync(SRC, 'utf8').replace(/\r\n/g, '\n');

// 1) 预设身份与显示名（上游 id=`preset-standard` / config.id=`standard` / order=1）
const before = text;
text = text.replace('    - id: preset-standard\n', '    - id: preset-standard-assistant\n');
text = text.replace(
  '        id: standard\n',
  '        id: standard-assistant\n' +
    '        name: 标·准· 模式\n' +
    '        description: 标准模式的全套提示词与工具；系统提示词第一项换成「You are a helpful software engineer assistant.」（其余段与标准模式一致）。\n',
);
text = text.replace('        order: 1\n', '        order: 6\n');
if (text === before) throw new Error('上游结构不符：没找到 preset-standard / id: standard / order: 1');

// 2) 用本地插件行替换标准模式的 persona 行（整块，含其 config 子行）。
const PERSONA_RE = / {10}- id: persona\n {12}name: '@deepseek-ai\/dsh-persona'\n(?: {12}config:\n(?: {14}[^\n]*\n)*)?/;
if (!PERSONA_RE.test(text)) throw new Error('上游结构不符：没找到 persona 插件块');
const REPLACEMENT = [
  '          - id: persona-prefix-first',
  "            name: './persona-prefix-first.mjs'",
  '            config:',
  '              prefix: You are a helpful software engineer assistant.',
  '              order: -2000',
  '',
].join('\n');
text = text.replace(PERSONA_RE, REPLACEMENT);

// 3) 自检：不得再有对上游 persona 的引用、不得包含已删除的 list-agents 行。
if (text.includes("'@deepseek-ai/dsh-persona'")) throw new Error('生成结果仍引用内置 persona');
if (text.includes('list-agents')) throw new Error('生成结果仍引用已移除的 list-agents 子路径');

fs.writeFileSync(OUT, HEADER + text, 'utf8');
console.log(`written ${OUT} (${fs.statSync(OUT).size} bytes) from ${SRC}`);
