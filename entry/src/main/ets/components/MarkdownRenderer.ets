/**
 * Markdown 渲染组件 (ArkTS 兼容版本)
 * 
 * 注意: @luvi/lv-markdown-in 需通过 ohpm 安装
 * 当前使用简化实现
 */
 
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
 
const DOMAIN = 0xFF00;
const TAG = 'MarkdownRenderer';
 
@Component
export struct MarkdownRenderer {
  @Prop content: string = '';
 
  build() {
    Scroll() {
      Column() {
        if (this.hasMermaid(this.content)) {
          this.MermaidSection()
        }
        
        Text(this.content)
          .fontSize(14)
          .width('100%')
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }
 
  @Builder
  MermaidSection(): void {
    Column() {
      Text('📊 流程图')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 10 })
 
      webview.WebView({ controller: new webview.WebviewController() })
        .width('100%')
        .height(200)
        .backgroundColor('#F5F5F5')
    }
    .width('100%')
    .padding(10)
    .margin({ bottom: 10 })
  }
 
  hasMermaid(content: string): boolean {
    return content.includes('```mermaid')
  }
}
 
@Component
export struct SimpleMarkdownText {
  @Prop content: string = ''
 
  build() {
    Column() {
      if (this.isCodeBlock(this.content)) {
        Text(this.extractCode(this.content))
          .fontSize(12)
          .fontFamily('monospace')
          .backgroundColor('#F5F5F5')
          .padding(8)
          .width('100%')
      } else {
        Text(this.content)
          .fontSize(14)
          .maxLines(20)
      }
    }
    .width('100%')
  }
 
  isCodeBlock(content: string): boolean {
    return content.startsWith('```') && content.endsWith('```')
  }
 
  extractCode(content: string): string {
    const startIndex: number = content.indexOf('\n')
    const endIndex: number = content.lastIndexOf('```')
    if (startIndex > 0 && endIndex > startIndex) {
      return content.substring(startIndex + 1, endIndex)
    }
    return content
  }
}