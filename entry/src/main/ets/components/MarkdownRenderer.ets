/**
 * Markdown 渲染组件
 * 使用 @luvi/lv-markdown-in 3.x 版本的 Markdown 组件
 */

import { Markdown, MarkdownController, MdCallback } from '@luvi/lv-markdown-in';

@Component
export struct MarkdownRenderer {
  @Prop content: string = '';
  @Prop fontSize: number = 16;
  @Prop fontColor: string = '#333333';
  private controller: MarkdownController = new MarkdownController();

  build() {
    Column() {
      Markdown({
        text: this.content,
        controller: this.controller
      })
    }
    .width('100%')
  }
}

@Component
export struct SimpleMarkdownText {
  @Prop content: string = '';
  @Prop fontSize: number = 16;
  @Prop fontColor: string = '#333333';
  private controller: MarkdownController = new MarkdownController();

  build() {
    Column() {
      Markdown({
        text: this.content,
        controller: this.controller
      })
    }
    .width('100%')
  }
}