/**
 * Markdown 渲染组件
 * 使用 @luvi/lv-markdown-in 渲染 Markdown 内容
 */

import { lvMarkdownIn } from '@luvi/lv-markdown-in';

@Component
export struct MarkdownRenderer {
  @Prop content: string = '';
  @Prop fontSize: number = 14;
  @Prop fontColor: string = '#333333';

  build() {
    Column() {
      lvMarkdownIn({ text: this.content })
    }
    .width('100%')
  }
}

@Component
export struct SimpleMarkdownText {
  @Prop content: string = '';
  @Prop fontSize: number = 14;
  @Prop fontColor: string = '#333333';

  build() {
    Column() {
      lvMarkdownIn({ text: this.content })
    }
    .width('100%')
  }
}