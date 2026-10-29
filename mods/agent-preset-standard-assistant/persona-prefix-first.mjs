/**
 * persona-prefix-first —— 把 `deployment:persona-prefix` 段注册到系统提示词最前面。
 *
 * 为什么需要它（而不是直接用 @deepseek-ai/dsh-persona）：
 *   * 内置 persona 行的段 order 固定为 `getSectionOrder('DEPLOYMENT_PERSONA_PREFIX')` = 0；
 *   * harness 身份段 `harness:identity` 的 order 是 -1000（由 dsh-system-prompt 的
 *     includeHarnessIdentity 注册），所以内置 persona 永远排在身份段之后。
 *   * 本插件挂在该 preset 的 scope 里，用**同名遮蔽**（scoped section 覆盖 global 同名段）
 *     把 `deployment:persona-prefix` 重新注册到任意 order（默认 -2000），于是它成为整份
 *     系统提示词的第一段；其他段（含 harness:identity、工具引导、UI/环境段）保持原顺序。
 *
 * 约定：section 的 order 必须是有限值；文本默认不插值，需要 {{variable}} 时可自行传入。
 */
export const name = 'persona-prefix-first';
export const inject = ['systemPrompt'];

export function apply(ctx, config) {
  const prefix = config?.prefix ?? 'You are a helpful software engineer assistant.';
  const order = config?.order ?? -2000;
  const sectionName = config?.sectionName ?? 'deployment:persona-prefix';

  ctx.effect(
    () =>
      ctx.systemPrompt.section({
        name: sectionName,
        order,
        text: prefix,
      }),
    'persona-prefix-first.section()',
  );
}
