/**
 * sidebar-panellist-collapse —— 给左侧栏加一个「展开 / 收起全局面板列表」按钮。
 *
 * 背景：左侧栏顶部是皮肤的角色动图，动图下面是「全局面板」列表（插件 / 任务看板 /
 * 技能中心 / 智能体 / Git / SSH / 更多）。这份列表占掉侧栏一大块高度，工作区只剩很少
 * 空间。本插件在侧栏底部（`sidebar.footer.action` 官方扩展位）加一个折叠按钮，
 * 折叠时隐藏那份列表，把空间让给工作区；状态存 localStorage，刷新后保持。
 *
 * 实现要点：
 *   - 按钮通过官方 slot 注册（不替换任何内置 UI，replaceRisk: none）；
 *   - 折叠效果用一条样式规则实现：`body[data-dsh-panellist-collapsed]` 下隐藏
 *     `[data-slot="sidebar.panellist"]`（槽位座位），并带一条 nav 兜底选择器；
 *   - 文案走 Client locale 服务（zh / en 字典 + 当前语言兜底）；
 *   - 所有资源都在 apply 内用 ctx.effect 注册，卸载时自动清理。
 */
window.__ModuleLoader__.load({
  id: '@local/dsh-panellist-collapse',
  factory(require) {
    const React = require('react');
    const h = React.createElement;

    const NS = 'dsh-panellist-collapse';
    const STORAGE_KEY = 'dsh.panellist.collapsed';
    const BODY_ATTR = 'data-dsh-panellist-collapsed';
    const DICTS = {
      zh: { collapse: '收起面板列表', expand: '展开面板列表' },
      en: { collapse: 'Collapse panel list', expand: 'Expand panel list' },
    };

    /** 折叠状态变更的本地监听（同一个页面里可能挂多个组件实例）。 */
    const listeners = new Set();

    const readCollapsed = () => {
      try { return window.localStorage.getItem(STORAGE_KEY) === '1'; } catch { return false; }
    };
    const writeCollapsed = (value) => {
      try { window.localStorage.setItem(STORAGE_KEY, value ? '1' : '0'); } catch { /* 隐私模式等场景忽略 */ }
    };
    const notify = () => { for (const listener of [...listeners]) listener(); };

    const CSS = [
      /* 折叠：隐藏左侧栏的「全局面板」列表（就是那个 nav）。
         注意 slot 座位属性是按面板项逐项渲染的，不能用它匹配整列。 */
      'body[data-dsh-panellist-collapsed] nav[role="navigation"],',
      'body[data-dsh-panellist-collapsed] [class*="panelList"] { display: none !important; }',
      /* 按钮外观：尺寸用内联样式兜底（宿主对 footer button 有更具体的规则），
         这里只放内联表达不了的交互态。 */
      '.dsh-panellist-collapse-button:hover { opacity: 1 !important; background: color-mix(in srgb, currentColor 14%, transparent) !important; }',
      '.dsh-panellist-collapse-button:active { opacity: 1 !important; background: color-mix(in srgb, currentColor 22%, transparent) !important; }',
      '.dsh-panellist-collapse-button:focus-visible { outline: 2px solid color-mix(in srgb, currentColor 45%, transparent); outline-offset: 2px; }',
    ].join('\n');

    const BUTTON_STYLE = {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      width: 28,
      height: 28,
      padding: 0,
      border: 0,
      borderRadius: 8,
      background: 'transparent',
      color: 'inherit',
      cursor: 'pointer',
      opacity: 0.68,
      transition: 'background-color .15s ease, opacity .15s ease',
    };
    const CELL_STYLE = {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      flex: '0 0 auto',
      width: 36,
      height: 36,
    };

    return {
      inject: ['slots', 'locale'],
      apply(ctx) {
        /* 1) 字典：中文/英文各注册一次，其余语言走回退。 */
        ctx.effect(() => {
          const disposers = ['zh', 'zh-CN', 'en', 'en-US'].map((id) =>
            ctx.locale.register(NS, id, id.toLowerCase().startsWith('zh') ? DICTS.zh : DICTS.en));
          return () => { for (const off of disposers) off(); };
        }, 'panellist-collapse.locale');

        /* 2) 样式表：折叠规则 + 按钮外观。 */
        ctx.effect(() => {
          const style = document.createElement('style');
          style.setAttribute('data-dsh-panellist-collapse', '');
          style.textContent = CSS;
          document.head.append(style);
          return () => style.remove();
        }, 'panellist-collapse.style');

        /* 3) 把折叠状态投射到 body 属性上，并随状态变化保持同步。 */
        ctx.effect(() => {
          const syncBody = () => {
            const body = document.body;
            if (!body) return;
            if (readCollapsed()) body.setAttribute(BODY_ATTR, '');
            else body.removeAttribute(BODY_ATTR);
          };
          syncBody();
          listeners.add(syncBody);
          return () => listeners.delete(syncBody);
        }, 'panellist-collapse.body-attribute');

        const isChinese = () => String(ctx.locale.getLocale().active || '').toLowerCase().startsWith('zh');
        const fallbackLabel = (collapsed) => (isChinese()
          ? (collapsed ? DICTS.zh.expand : DICTS.zh.collapse)
          : (collapsed ? DICTS.en.expand : DICTS.en.collapse));

        function ToggleButton() {
          const [collapsed, setCollapsed] = React.useState(readCollapsed);
          const [, bumpLocale] = React.useState(0);

          React.useEffect(() => {
            const onState = () => setCollapsed(readCollapsed());
            const onLocale = () => bumpLocale((n) => n + 1);
            listeners.add(onState);
            const unsubscribe = ctx.locale.subscribe(onLocale);
            return () => { listeners.delete(onState); unsubscribe(); };
          }, []);

          const key = collapsed ? 'expand' : 'collapse';
          const translated = ctx.locale.bind(NS)(key);
          const label = translated && translated !== key ? translated : fallbackLabel(collapsed);

          return h('span', { className: 'dsh-panellist-collapse-cell', style: CELL_STYLE },
            h('button', {
              type: 'button',
              className: 'dsh-panellist-collapse-button',
              style: BUTTON_STYLE,
              title: label,
              'aria-label': label,
              'aria-expanded': collapsed ? 'false' : 'true',
              onClick: () => { writeCollapsed(!readCollapsed()); notify(); },
            }, h('svg', {
              viewBox: '0 0 16 16',
              width: 16,
              height: 16,
              fill: 'none',
              stroke: 'currentColor',
              strokeWidth: 1.6,
              strokeLinecap: 'round',
              strokeLinejoin: 'round',
              'aria-hidden': true,
            }, h('path', { d: collapsed ? 'M3.5 6 8 10.5 12.5 6' : 'M3.5 10 8 5.5 12.5 10' }))));
        }

        /* 4) 挂到侧栏底部的官方扩展位（replaceRisk: none，不替换任何内置项）。 */
        ctx.slots.inject('sidebar.footer.action', () => ctx.slots.register({
          name: 'sidebar.footer.action',
          id: 'panellist-collapse',
          order: -10,
        }, ToggleButton));
      },
    };
  },
});
