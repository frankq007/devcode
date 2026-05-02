/**
 * 文件预览组件
 * 
 * 功能：
 * - 图片预览
 * - Markdown/文本预览
 * - PDF 调用系统打开
 * - 代码文件语法高亮显示
 */

import { WebView } from '@kit.ArkWeb';
import { image } from '@kit.ImageKit';
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

  private webViewController: WebView.WebviewController = new WebView.WebviewController();

  aboutToAppear(): void {
    // 从路由参数获取文件信息
    // const params = router.getParams() as ESObject;
    // this.fileUrl = params.fileUrl || '';
    // this.fileName = params.fileName || '';
    // this.serverIp = params.serverIp || '100.64.0.2';
    // this.httpPort = params.httpPort || 8081;

    // 根据文件名判断类型
    this.fileType = this.getFileType(this.fileName);
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('文件预览')
          .fontSize(20)
          .fontWeight(FontWeight.Bold);

        Text(this.fileName)
          .fontSize(14)
          .fontColor('#888888')
          .margin({ left: 10 });
      }
      .width('100%')
      .height(50)
      .padding({ left: 20, right: 20 })
      .backgroundColor('#FFFFFF');

      // 预览区域
      if (this.fileType === 'image') {
        this.ImagePreview();
      } else if (this.fileType === 'markdown' || this.fileType === 'text') {
        this.TextPreview();
      } else if (this.fileType === 'code') {
        this.CodePreview();
      } else {
        this.GenericPreview();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5');
  }

  /**
   * 图片预览
   */
  @Builder
  ImagePreview(): void {
    Column() {
      Image(this.fileUrl)
        .width('100%')
        .height('80%')
        .objectFit(ImageFit.Contain)
        .alt($r('app.media.startIcon'))
        .onError(() => {
          hilog.error(DOMAIN, TAG, `Image load error: ${this.fileUrl}`);
        });

      // 文件信息
      Row() {
        Text(`文件: ${this.fileName}`)
          .fontSize(12)
          .fontColor('#888888');
      }
      .width('100%')
      .padding(10);
    }
    .width('100%')
    .height('100%');
  }

  /**
   * 文本/Markdown 预览
   */
  @Builder
  TextPreview(): void {
    Column() {
      // 使用 WebView 加载内容
      WebView({ controller: this.webViewController })
        .width('100%')
        .height('80%')
        .backgroundColor('#FFFFFF')
        .onPageEnd(() => {
          // 加载完成后可以执行操作
        });

      // 对于 Markdown 文件，使用 WebView 显示
      // 构建完整 URL
      // this.webViewController.loadUrl(this.fileUrl);
    }
    .width('100%')
    .height('100%');
  }

  /**
   * 代码文件预览
   */
  @Builder
  CodePreview(): void {
    Column() {
      // 代码文件使用 WebView + highlight.js 显示
      WebView({ controller: this.webViewController })
        .width('100%')
        .height('80%')
        .backgroundColor('#1E1E1E');

      // 文件信息
      Row() {
        Text(`代码文件: ${this.fileName}`)
          .fontSize(12)
          .fontColor('#888888');

        Text(`语言: ${this.getCodeLanguage(this.fileName)}`)
          .fontSize(12)
          .fontColor('#888888')
          .margin({ left: 10 });
      }
      .width('100%')
      .padding(10)
      .backgroundColor('#FFFFFF');
    }
    .width('100%')
    .height('100%');
  }

  /**
   * 通用文件预览（无法直接预览）
   */
  @Builder
  GenericPreview(): void {
    Column() {
      Column() {
        Text('📁')
          .fontSize(60);

        Text(this.fileName)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 10 });

        Text('此文件类型无法直接预览')
          .fontSize(14)
          .fontColor('#888888')
          .margin({ top: 5 });

        Button('下载文件')
          .width('60%')
          .height(50)
          .backgroundColor('#4CAF50')
          .margin({ top: 20 })
          .onClick(() => {
            this.downloadFile();
          });
      }
      .width('100%')
      .height('80%')
      .justifyContent(FlexAlign.Center);
    }
    .width('100%')
    .height('100%');
  }

  /**
   * 获取文件类型
   */
  getFileType(fileName: string): string {
    const ext = fileName.split('.').pop()?.toLowerCase() || '';

    const imageExts = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'bmp'];
    const markdownExts = ['md', 'markdown'];
    const textExts = ['txt', 'log', 'csv'];
    const codeExts = ['js', 'ts', 'jsx', 'tsx', 'py', 'java', 'cpp', 'c', 'go', 'rs', 'rb', 'php', 'swift', 'kt', 'json', 'yaml', 'yml', 'xml', 'html', 'css', 'scss', 'sql', 'sh', 'bat'];

    if (imageExts.includes(ext)) return 'image';
    if (markdownExts.includes(ext)) return 'markdown';
    if (textExts.includes(ext)) return 'text';
    if (codeExts.includes(ext)) return 'code';

    return 'generic';
  }

  /**
   * 获取代码语言
   */
  getCodeLanguage(fileName: string): string {
    const ext = fileName.split('.').pop()?.toLowerCase() || '';

    const langMap: Record<string, string> = {
      'js': 'JavaScript',
      'ts': 'TypeScript',
      'jsx': 'React JSX',
      'tsx': 'React TSX',
      'py': 'Python',
      'java': 'Java',
      'cpp': 'C++',
      'c': 'C',
      'go': 'Go',
      'rs': 'Rust',
      'rb': 'Ruby',
      'php': 'PHP',
      'swift': 'Swift',
      'kt': 'Kotlin',
      'json': 'JSON',
      'yaml': 'YAML',
      'yml': 'YAML',
      'xml': 'XML',
      'html': 'HTML',
      'css': 'CSS',
      'scss': 'SCSS',
      'sql': 'SQL',
      'sh': 'Shell',
      'bat': 'Batch'
    };

    return langMap[ext] || ext.toUpperCase();
  }

  /**
   * 下载文件
   */
  downloadFile(): void {
    hilog.info(DOMAIN, TAG, `Download file: ${this.fileUrl}`);
    // 实际实现需要使用 @ohos.net.http 进行下载
    // 或调用系统分享功能
  }
}

/**
 * 文件预览卡片组件（用于文件列表）
 */
@Component
export struct FilePreviewCard {
  @Prop file: FileInfo;
  @Prop serverIp: string = '';
  @Prop httpPort: number = 8081;

  build() {
    Column() {
      // 文件图标
      Row() {
        Text(this.getFileIcon())
          .fontSize(24);

        Column() {
          Text(this.file.name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium);

          Text(this.formatSize(this.file.size))
            .fontSize(12)
            .fontColor('#888888');
        }
        .margin({ left: 10 });
      }
      .width('100%')
      .padding(10);

      // 预览按钮
      Button('预览')
        .width('80%')
        .height(35)
        .backgroundColor('#4CAF50')
        .onClick(() => {
          this.openPreview();
        });
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#FFFFFF')
    .borderRadius(8);
  }

  /**
   * 获取文件图标
   */
  getFileIcon(): string {
    const ext = this.file.name.split('.').pop()?.toLowerCase() || '';

    const iconMap: Record<string, string> = {
      'png': '🖼️',
      'jpg': '🖼️',
      'jpeg': '🖼️',
      'gif': '🖼️',
      'webp': '🖼️',
      'svg': '🖼️',
      'md': '📝',
      'txt': '📄',
      'log': '📋',
      'json': '📋',
      'js': '💻',
      'ts': '💻',
      'py': '💻',
      'java': '💻',
      'cpp': '💻',
      'c': '💻',
      'html': '🌐',
      'css': '🎨',
      'pdf': '📕',
      'zip': '📦'
    };

    return iconMap[ext] || '📁';
  }

  /**
   * 格式化文件大小
   */
  formatSize(size: number): string {
    if (size < 1024) return `${size} B`;
    if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`;
    return `${(size / 1024 / 1024).toFixed(1)} MB`;
  }

  /**
   * 打开预览
   */
  openPreview(): void {
    // 实际实现需要使用 router 跳转到 FilePreviewPage
    // router.pushUrl({
    //   url: 'pages/FilePreviewPage',
    //   params: {
    //     fileUrl: `http://${this.serverIp}:${this.httpPort}${this.file.url}`,
    //     fileName: this.file.name,
    //     serverIp: this.serverIp,
    //     httpPort: this.httpPort
    //   }
    // });
  }
}