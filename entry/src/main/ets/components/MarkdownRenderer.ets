/**
 * Markdown 渲染组件
 * 
 * 功能：
 * - 使用 @luvi/lv-markdown-in 渲染 Markdown
 * - 代码块语法高亮 (highlight.js)
 * - Mermaid 图表通过 WebView 渲染
 * 
 * 安装依赖：
 * ohpm install @luvi/lv-markdown-in
 */

import { WebView } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { MarkdownController } from '@luvi/lv-markdown-in';

const DOMAIN = 0xFF00;
const TAG = 'MarkdownRenderer';

@Component
export struct MarkdownRenderer {
  @Prop content: string = '';
  @State renderedContent: string = '';
  private controller: WebView.WebviewController = new WebView.WebviewController();

  aboutToAppear(): void {
    // 预处理内容，提取 Mermaid 代码块
    this.renderedContent = this.preprocessMarkdown(this.content);
  }

  build() {
    Scroll() {
      Column() {
        // 检测是否包含 Mermaid 图表
        if (this.hasMermaid(this.content)) {
          // 使用 WebView 渲染 Mermaid
          this.MermaidSection();
        }

        // Markdown 文本内容
        // 注：需要安装 @luvi/lv-markdown-in 后使用
        // 目前使用 RichEditor 作为替代方案
        RichEditor({ controller: new RichEditorController() })
          .width('100%')
          .height('100%')
          .borderRadius(8)
          .backgroundColor('#FFFFFF')
          .onReady(() => {
            this.renderMarkdown();
          });
      }
    }
    .width('100%')
    .height('100%');
  }

  /**
   * Mermaid 图表渲染区域
   */
  @Builder
  MermaidSection(): void {
    Column() {
      Text('📊 流程图')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 10 });

      // WebView 渲染 Mermaid
      WebView({ controller: this.controller })
        .width('100%')
        .height(200)
        .backgroundColor('#F5F5F5')
        .onPageEnd(() => {
          // 加载完成后执行渲染
          const mermaidCode = this.extractMermaidCode(this.content);
          if (mermaidCode) {
            this.controller.runJavaScript(`renderMermaid('${mermaidCode}')`);
          }
        });
    }
    .width('100%')
    .padding(10)
    .margin({ bottom: 10 });
  }

  /**
   * 检测是否包含 Mermaid 代码块
   */
  hasMermaid(content: string): boolean {
    return content.includes('```mermaid');
  }

  /**
   * 提取 Mermaid 代码
   */
  extractMermaidCode(content: string): string {
    const match = content.match(/```mermaid\n([\s\S]*?)```/);
    return match ? match[1].trim() : '';
  }

  /**
   * 预处理 Markdown 内容
   */
  preprocessMarkdown(content: string): string {
    // 移除 Mermaid 代码块（由 WebView 单独处理）
    let processed = content.replace(/```mermaid\n[\s\S]*?```/g, '');
    
    // 处理代码高亮标记
    // 注：需要 highlight.js 集成
    return processed;
  }

  /**
   * 渲染 Markdown 到 RichEditor
   */
  renderMarkdown(): void {
    // 简化实现：将 Markdown 作为纯文本显示
    // 完整实现需要 @luvi/lv-markdown-in
    
    // RichEditor 示例操作
    // 实际应使用 Markdown 库的解析结果
  }
}

/**
 * 简化的 Markdown 显示组件
 * 用于消息列表中的短内容显示
 */
@Component
export struct SimpleMarkdownText {
  @Prop content: string = '';

  build() {
    Column() {
      // 简单处理：检测代码块并特殊显示
      if (this.isCodeBlock(this.content)) {
        Column() {
          Text(this.extractCode(this.content))
            .fontSize(12)
            .fontFamily('monospace')
            .backgroundColor('#F5F5F5')
            .padding(8)
            .width('100%');
        }
        .width('100%');
      } else {
        // 普通文本
        Text(this.content)
          .fontSize(14)
          .maxLines(20);
      }
    }
    .width('100%');
  }

  isCodeBlock(content: string): boolean {
    return content.startsWith('```') && content.endsWith('```');
  }

  extractCode(content: string): string {
    // 移除代码块标记
    return content.replace(/^```[a-z]*\n/, '').replace(/```$/, '');
  }
}

/**
 * Mermaid WebView HTML 内容
 * 用于 rawfile 中的 mermaid_renderer.html
 */
export const MERMAID_RENDERER_HTML = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
  <style>
    body {
      margin: 0;
      padding: 10px;
      background: #f5f5f5;
    }
    .mermaid {
      background: #fff;
      border-radius: 8px;
      padding: 10px;
    }
  </style>
</head>
<body>
  <div class="mermaid" id="chart"></div>
  <script>
    mermaid.initialize({ startOnLoad: false, theme: 'default' });
    
    function renderMermaid(code) {
      const chartDiv = document.getElementById('chart');
      chartDiv.textContent = code;
      mermaid.init(undefined, '.mermaid');
    }
  </script>
</body>
</html>
`;