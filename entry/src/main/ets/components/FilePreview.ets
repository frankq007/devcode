/**
 * 文件预览组件 (ArkTS 兼容版本)
 */
 
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { FileInfo } from '../common/Types';
 
const DOMAIN = 0xFF00;
const TAG = 'FilePreview';
 
@Entry
@Component
struct FilePreviewPage {
  @State fileUrl: string = '';
  @State fileName: string = '';
  @State fileType: string = '';
  @State serverIp: string = '';
  @State httpPort: number = 8081;
 
  aboutToAppear(): void {
    this.fileType = this.getFileType(this.fileName)
  }
 
  build() {
    Column() {
      Row() {
        Text('文件预览')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
 
        Text(this.fileName)
          .fontSize(14)
          .fontColor('#888888')
          .margin({ left: 10 })
      }
      .width('100%')
      .height(50)
      .padding({ left: 20, right: 20 })
      .backgroundColor('#FFFFFF')
 
      if (this.fileType === 'image') {
        this.ImagePreview()
      } else if (this.fileType === 'markdown' || this.fileType === 'text') {
        this.TextPreview()
      } else if (this.fileType === 'code') {
        this.CodePreview()
      } else {
        this.GenericPreview()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
 
  @Builder
  ImagePreview(): void {
    Column() {
      Image(this.fileUrl)
        .width('100%')
        .height('80%')
        .objectFit(ImageFit.Contain)
        .alt($r('app.media.startIcon'))
    }
    .width('100%')
    .height('100%')
  }
 
  @Builder
  TextPreview(): void {
    Column() {
      webview.WebView({ controller: new webview.WebviewController() })
        .width('100%')
        .height('80%')
        .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
  }
 
  @Builder
  CodePreview(): void {
    Column() {
      webview.WebView({ controller: new webview.WebviewController() })
        .width('100%')
        .height('80%')
        .backgroundColor('#1E1E1E')
    }
    .width('100%')
    .height('100%')
  }
 
  @Builder
  GenericPreview(): void {
    Column() {
      Column() {
        Text('📁')
          .fontSize(60)
 
        Text(this.fileName)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 10 })
 
        Text('此文件类型无法直接预览')
          .fontSize(14)
          .fontColor('#888888')
          .margin({ top: 5 })
 
        Button('下载文件')
          .width('60%')
          .height(50)
          .backgroundColor('#4CAF50')
          .margin({ top: 20 })
      }
      .width('100%')
      .height('80%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
  }
 
  getFileType(fileName: string): string {
    if (fileName.endsWith('.png') || fileName.endsWith('.jpg') || fileName.endsWith('.jpeg') || fileName.endsWith('.gif') || fileName.endsWith('.webp')) {
      return 'image'
    }
    if (fileName.endsWith('.md') || fileName.endsWith('.markdown')) {
      return 'markdown'
    }
    if (fileName.endsWith('.txt') || fileName.endsWith('.log')) {
      return 'text'
    }
    if (fileName.endsWith('.js') || fileName.endsWith('.ts') || fileName.endsWith('.py') || fileName.endsWith('.json') || fileName.endsWith('.html')) {
      return 'code'
    }
    return 'generic'
  }
}
 
@Component
export struct FilePreviewCard {
  @Prop file: FileInfo
  @Prop serverIp: string = ''
  @Prop httpPort: number = 8081
 
  build() {
    Column() {
      Row() {
        Text(this.getFileIcon())
          .fontSize(24)
 
        Column() {
          Text(this.file.name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
 
          Text(this.formatSize(this.file.size))
            .fontSize(12)
            .fontColor('#888888')
        }
        .margin({ left: 10 })
      }
      .width('100%')
      .padding(10)
 
      Button('预览')
        .width('80%')
        .height(35)
        .backgroundColor('#4CAF50')
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#FFFFFF')
    .borderRadius(8)
  }
 
  getFileIcon(): string {
    if (this.file.name.endsWith('.png') || this.file.name.endsWith('.jpg')) {
      return '🖼️'
    }
    if (this.file.name.endsWith('.md') || this.file.name.endsWith('.txt')) {
      return '📄'
    }
    if (this.file.name.endsWith('.json')) {
      return '📋'
    }
    if (this.file.name.endsWith('.js') || this.file.name.endsWith('.ts')) {
      return '💻'
    }
    return '📁'
  }
 
  formatSize(size: number): string {
    if (size < 1024) {
      return size.toString() + ' B'
    }
    if (size < 1024 * 1024) {
      const kb: number = size / 1024
      return kb.toFixed(1) + ' KB'
    }
    const mb: number = size / 1024 / 1024
    return mb.toFixed(1) + ' MB'
  }
}