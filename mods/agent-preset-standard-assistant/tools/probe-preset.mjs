// 校验探针：读出指定 preset 的工具清单 + 装配后的系统提示词，落盘 JSON。
//
// 挂法（临时 profile 的 cordis.patch.yml 顶层插入一行）：
//   - insert:
//       - id: probe-preset
//         name: './probe-preset.mjs'
//         config:
//           presetIds: ['standard', 'standard-assistant']
//           outDir: 'D:/.../probe'
//           delayMs: 6000
//
// 每个 preset 写 <outDir>/<id>.json 与 <outDir>/<id>.done；全部结束后写 <outDir>/all.done。
// 单个 preset 装配失败写 <outDir>/<id>.error.txt，不影响其余 preset。
//
// 为什么能这样读：agentPresets.acquireScope(id) 给出该 preset 的 standing scope 键，
// tools.view(scopeKey) 等价于模型可见的工具目录，systemPrompt.assemble({ scope })
// 等价于该模式每次请求的提示词装配（段 + 上下文 + 工具 schema + 变量）。
import fs from 'node:fs/promises';
import path from 'node:path';

export const name = 'probe-preset';
export const inject = ['agentPresets', 'systemPrompt', 'tools'];

export function apply(ctx, config) {
  const delayMs = config?.delayMs ?? 6000;
  const ids = Array.isArray(config?.presetIds)
    ? config.presetIds
    : config?.presetId
      ? [config.presetId]
      : [];
  const outDir = config?.outDir ?? (config?.outFile ? path.dirname(config.outFile) : undefined);
  if (!outDir || ids.length === 0) return;

  // 用全局定时器脱离激活帧：注册表诊断会等整棵 Host 树 settle，而本行自己就在树里。
  globalThis.setTimeout(async () => {
    await fs.mkdir(outDir, { recursive: true });
    for (const id of ids) {
      const base = path.join(outDir, String(id).replace(/[^\w.-]/g, '_'));
      let lease;
      try {
        lease = await ctx.agentPresets.acquireScope(id);
        const view = ctx.tools.view(lease.key);
        const asm = await ctx.systemPrompt.assemble({ scope: lease.key });
        const data = {
          preset: id,
          tools: [...view.visible.keys()].sort(),
          sections: (asm.sections ?? []).map((s) => ({ name: s.name, text: s.text ?? '' })),
          contexts: (asm.contexts ?? []).map((c) => ({ name: c.name, text: c.text ?? '', required: c.required })),
        };
        await fs.writeFile(base + '.json', JSON.stringify(data, null, 2), 'utf8');
        await fs.writeFile(base + '.done', new Date().toISOString(), 'utf8');
      } catch (error) {
        await fs.writeFile(base + '.error.txt', String(error?.stack ?? error), 'utf8');
      } finally {
        if (lease) { try { await lease[Symbol.asyncDispose](); } catch { /* ignore */ } }
      }
    }
    await fs.writeFile(path.join(outDir, 'all.done'), new Date().toISOString(), 'utf8');
  }, delayMs);
}
