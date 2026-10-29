/**
 * sidebar-panellist-collapse —— 左侧栏「全局面板列表」的展开 / 收起控制。
 *
 * 位置：按钮插在面板列表（`nav[role="navigation"]`）之后、工作区之前，作为一条很薄的折叠条。
 * 折叠行为：只把列表的**高度**收掉，保留它自己的 `margin-top`。
 *
 * 为什么不能用 display:none（重要）：
 *   orca-link 皮肤的动图舞台是靠面板列表自身的 margin-top 撑出来的
 *   （patches.css: `[data-surface=sidebar] > :first-child > nav { margin-top:
 *   calc(var(--orca-stage, 300px) - 116px) }`）。`display:none` 会把这条 margin 一起
 *   去掉，动图的舞台就塌了、工作区顶上来盖住动图。所以这里用 height: 0 + overflow: hidden，
 *   margin 保留 → 动图位置完全不变，工作区停在动图下方。
 *
 * 状态存在 localStorage，刷新/重启保持；文案走 Client locale（zh/en + 当前语言兜底）。
 */
window.__ModuleLoader__.load({
  id: '@local/dsh-panellist-collapse',
  factory(require) {
    const NS = 'dsh-panellist-collapse';
    const STORAGE_KEY = 'dsh.panellist.collapsed';
    const BODY_ATTR = 'data-dsh-panellist-collapsed';
    const ROW_CLASS = 'dsh-panellist-collapse-row';
    const BUTTON_CLASS = 'dsh-panellist-collapse-button';
    const SVG_NS = 'http://www.w3.org/2000/svg';

    const DICTS = {
      zh: { collapse: '收起面板列表', expand: '展开面板列表' },
      en: { collapse: 'Collapse panel list', expand: 'Expand panel list' },
    };

    const readCollapsed = () => {
      try { return window.localStorage.getItem(STORAGE_KEY) === '1'; } catch { return false; }
    };
    const writeCollapsed = (value) => {
      try { window.localStorage.setItem(STORAGE_KEY, value ? '1' : '0'); } catch { /* 隐私模式等场景忽略 */ }
    };
    const findNav = () =>
      document.querySelector('[data-dsh-surface="sidebar"] [class*="panelList"]') ||
      document.querySelector('[data-dsh-surface="sidebar"] nav') ||
      document.querySelector('[class*="panelList"]') ||
      document.querySelector('nav');

    const CSS = [
      /* 折叠：只收高度，保留列表自身的 margin-top（皮肤动图舞台靠它撑开）。 */
      'body[data-dsh-panellist-collapsed] [class*="panelList"],',
      'body[data-dsh-panellist-collapsed] [data-dsh-surface="sidebar"] nav {',
      '  height: 0 !important; min-height: 0 !important; max-height: 0 !important;',
      '  padding-top: 0 !important; padding-bottom: 0 !important;',
      '  margin-bottom: 0 !important; border: 0 !important; overflow: hidden !important;',
      '}',
      /* 折叠条：高度/尺寸用内联样式，这里只放交互态。 */
      '.' + BUTTON_CLASS + ':hover { opacity: 1 !important; background: color-mix(in srgb, currentColor 12%, transparent) !important; }',
      '.' + BUTTON_CLASS + ':active { background: color-mix(in srgb, currentColor 22%, transparent) !important; }',
      '.' + BUTTON_CLASS + ':focus-visible { outline: 2px solid color-mix(in srgb, currentColor 45%, transparent); outline-offset: 2px; }',
    ].join('\n');

    return {
      inject: ['locale'],
      apply(ctx) {
        /* 1) 字典：中文/英文各注册一次，其余语言走回退。 */
        ctx.effect(() => {
          const disposers = ['zh', 'zh-CN', 'en', 'en-US'].map((id) =>
            ctx.locale.register(NS, id, id.toLowerCase().startsWith('zh') ? DICTS.zh : DICTS.en));
          return () => { for (const off of disposers) off(); };
        }, 'panellist-collapse.locale');

        /* 2) 样式表：折叠规则 + 折叠条交互态。 */
        ctx.effect(() => {
          const style = document.createElement('style');
          style.setAttribute('data-dsh-panellist-collapse', '');
          style.textContent = CSS;
          document.head.append(style);
          return () => style.remove();
        }, 'panellist-collapse.style');

        /* 3) 折叠条 DOM（插在 nav 与工作区之间；不依赖任何 slot，因为「工作区之上」没有官方槽位）。 */
        const row = document.createElement('div');
        row.className = ROW_CLASS;
        row.style.cssText = 'display:flex;align-items:center;justify-content:center;height:22px;flex:0 0 auto;position:relative;z-index:2;';

        const button = document.createElement('button');
        button.type = 'button';
        button.className = BUTTON_CLASS;
        button.style.cssText = [
          'display:inline-flex', 'align-items:center', 'justify-content:center',
          'width:32px', 'height:18px', 'padding:0', 'border:0', 'border-radius:6px',
          'background:transparent', 'color:inherit', 'cursor:pointer', 'opacity:.55',
          'transition:background-color .15s ease, opacity .15s ease',
        ].join(';');

        const svg = document.createElementNS(SVG_NS, 'svg');
        svg.setAttribute('viewBox', '0 0 16 16');
        svg.setAttribute('width', '14');
        svg.setAttribute('height', '14');
        svg.setAttribute('fill', 'none');
        svg.setAttribute('stroke', 'currentColor');
        svg.setAttribute('stroke-width', '1.6');
        svg.setAttribute('stroke-linecap', 'round');
        svg.setAttribute('stroke-linejoin', 'round');
        svg.setAttribute('aria-hidden', 'true');
        const svgPath = document.createElementNS(SVG_NS, 'path');
        svg.append(svgPath);
        button.append(svg);
        row.append(button);

        const t = (collapsed) => {
          const key = collapsed ? 'expand' : 'collapse';
          const translated = ctx.locale.bind(NS)(key);
          if (translated && translated !== key) return translated;
          const chinese = String(ctx.locale.getLocale().active || '').toLowerCase().startsWith('zh');
          return chinese ? DICTS.zh[key] : DICTS.en[key];
        };

        const render = () => {
          const collapsed = readCollapsed();
          if (collapsed) document.body.setAttribute(BODY_ATTR, '');
          else document.body.removeAttribute(BODY_ATTR);
          const label = t(collapsed);
          button.title = label;
          button.setAttribute('aria-label', label);
          button.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
          svgPath.setAttribute('d', collapsed ? 'M3.5 6 8 10.5 12.5 6' : 'M3.5 10 8 5.5 12.5 10');
        };

        /* 4) 把折叠条维持在 nav 之后；宿主重渲染后自动补回。 */
        let observer = null;
        const ensureAttached = () => {
          const nav = findNav();
          if (!nav || !nav.parentElement) {
            if (row.isConnected) row.remove();
            return;
          }
          if (row.parentElement !== nav.parentElement || row.previousElementSibling !== nav) {
            nav.insertAdjacentElement('afterend', row);
          }
          /* 侧栏收成窄条（rail）时列表不可见，折叠条也隐藏。 */
          row.style.display = nav.offsetWidth > 40 ? 'flex' : 'none';
        };

        button.addEventListener('click', () => {
          writeCollapsed(!readCollapsed());
          render();
        });

        render();
        ensureAttached();
        observer = new MutationObserver(() => ensureAttached());
        observer.observe(document.body, { childList: true, subtree: true });
        window.addEventListener('resize', ensureAttached);
        const unsubscribeLocale = ctx.locale.subscribe(() => render());

        ctx.effect(() => () => {
          if (observer) observer.disconnect();
          window.removeEventListener('resize', ensureAttached);
          unsubscribeLocale();
          row.remove();
          document.body.removeAttribute(BODY_ATTR);
        }, 'panellist-collapse.dom');
      },
    };
  },
});
