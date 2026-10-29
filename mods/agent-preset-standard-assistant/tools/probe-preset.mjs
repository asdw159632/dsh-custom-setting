// 校验探针：读出指定 preset 的工具清单 + 装配后的系统提示词，落盘 JSON。
//
// 挂法（临时 profile 的 cordis.patch.yml 顶层插入一行）：
//   - insert:
//       - id: probe-preset
//         name: './probe-preset.mjs'
//         config:
//           presetId: standard-assistant
//           outFile: 'D:/.../probe.json'
//           delayMs: 6000
//
// 为什么能这样读：agentPresets.acquireScope(id) 给出该 preset 的 standing scope 键，
// tools.view(scopeKey) 等价于模型可见的工具目录，systemPrompt.assemble({ scope })
// 等价于该模式每次请求的提示词装配（段 + 上下文 + 工具 schema + 变量）。
import fs from 'node:fs/promises';

export const name = 'probe-preset';
export const inject = ['agentPresets', 'systemPrompt', 'tools'];

export function apply(ctx, config) {
  const delayMs = config?.delayMs ?? 6000;
  const outFile = config?.outFile;

  // 用全局定时器脱离激活帧：注册表诊断会等整棵 Host 树 settle，而本行自己就在树里。
  globalThis.setTimeout(async () => {
    let lease;
    try {
      lease = await ctx.agentPresets.acquireScope(config.presetId);
      const view = ctx.tools.view(lease.key);
      const asm = await ctx.systemPrompt.assemble({ scope: lease.key });
      const data = {
        preset: config.presetId,
        tools: [...view.visible.keys()].sort(),
        sections: (asm.sections ?? []).map((s) => ({ name: s.name, text: s.text ?? '' })),
        contexts: (asm.contexts ?? []).map((c) => ({ name: c.name, text: c.text ?? '', required: c.required })),
      };
      await fs.writeFile(outFile, JSON.stringify(data, null, 2), 'utf8');
      await fs.writeFile(outFile + '.done', new Date().toISOString(), 'utf8');
    } catch (error) {
      await fs.writeFile(String(outFile) + '.error.txt', String(error?.stack ?? error), 'utf8');
    } finally {
      if (lease) { try { await lease[Symbol.asyncDispose](); } catch { /* ignore */ } }
    }
  }, delayMs);
}
