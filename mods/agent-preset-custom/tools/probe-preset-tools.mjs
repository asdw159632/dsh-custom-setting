/**
 * 校验用探针（由 verify.sh 拷进临时 profile）：列出指定 agent preset 对模型可见的工具名。
 *
 * 为什么能这样读：预设的「standing scope」就是该预设行的作用域；绑定到它的
 * agent scope 以它为父，二者工具视图的差别只有 agent 自己层里的注册项，而预设
 * 组合不注册这类工具。所以 view(presetScopeKey).visible 就等于该模式模型可见的
 * 工具目录（正好可以用来确认 read_image 是否真的注册成功）。
 *
 * 注意：不能在激活帧里 await 注册表诊断（diagnostic 会等整棵 Host 树 settle，
 * 而本行自己就在那棵树里 → 死锁），所以用定时器脱离激活帧再查。
 */
export const name = 'probe-preset-tools';
export const inject = ['agentPresets', 'tools'];

export function apply(ctx, config) {
  const presetIds = config?.presetIds ?? [config?.presetId ?? 'custom'];
  const delayMs = config?.delayMs ?? 4000;
  // 用全局定时器，避免依赖 cordis 的 timer 服务（不在 inject 里声明就用不了）。
  globalThis.setTimeout(async () => {
    for (const presetId of presetIds) {
      try {
        const lease = await ctx.agentPresets.acquireScope(presetId);
        try {
          const view = ctx.tools.view(lease.key);
          const names = [...view.visible.keys()].sort();
          console.log(`[probe] preset=${presetId} tools(${names.length}): ${names.join(', ')}`);
          for (const wanted of config?.expect ?? []) {
            console.log(`[probe] expect ${wanted}: ${view.visible.has(wanted) ? 'PRESENT' : 'MISSING'}`);
          }
        } finally {
          await lease[Symbol.asyncDispose]();
        }
      } catch (error) {
        console.log(`[probe] preset=${presetId} FAILED: ${error?.message ?? String(error)}`);
      }
    }
  }, delayMs);
}
