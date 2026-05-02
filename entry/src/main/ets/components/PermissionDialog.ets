/**
 * 权限弹窗组件
 * 
 * 功能：
 * - 显示权限请求详情
 * - 提供允许/拒绝/修改选项
 * - 支持修改命令
 */

import type { PermissionRequestMessage } from '../common/Types';

@Component
export struct PermissionDialog {
  @Prop request: PermissionRequestMessage | null = null;
  @Prop onAllow: () => void = () => {};
  @Prop onDeny: () => void = () => {};
  @Prop onModify: (newCmd: string) => void = (s: string) => {};
  @Prop onClose: () => void = () => {};

  @State showModifyInput: boolean = false;
  @State modifiedCommand: string = '';

  build() {
    // 全屏覆盖层
    Stack() {
      // 半透明背景
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
        .opacity(0.5)
        .onClick(() => {
          // 点击背景不关闭，防止误操作
        });

      // 弹窗卡片
      Column() {
        // 标题
        Text($r('app.string.permission_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 20 });

        // 解释
        if (this.request) {
          Column() {
            // 风险说明
            Text(this.request.explanation)
              .fontSize(16)
              .fontColor('#FF5722')
              .margin({ bottom: 15 });

            // 命令原文（等宽字体，浅灰背景）
            Column() {
              Text('命令原文:')
                .fontSize(12)
                .fontColor('#888888')
                .margin({ bottom: 5 });

              Text(this.request.command)
                .fontSize(14)
                .fontFamily('monospace')
                .backgroundColor('#F5F5F5')
                .padding(10)
                .borderRadius(4)
                .width('100%');
            }
            .width('100%')
            .margin({ bottom: 20 });
          }
        }

        // 修改输入框
        if (this.showModifyInput) {
          Column() {
            TextInput({ placeholder: '输入修改后的命令', text: this.modifiedCommand })
              .width('100%')
              .height(50)
              .margin({ bottom: 10 })
              .onChange((value) => {
                this.modifiedCommand = value;
              });

            Row() {
              Button('取消修改')
                .width('40%')
                .height(40)
                .backgroundColor('#666666')
                .onClick(() => {
                  this.showModifyInput = false;
                  this.modifiedCommand = '';
                });

              Button('提交修改')
                .width('40%')
                .height(40)
                .backgroundColor('#4CAF50')
                .onClick(() => {
                  if (this.modifiedCommand.trim()) {
                    this.onModify(this.modifiedCommand);
                  }
                });
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceAround);
          }
          .width('100%')
          .margin({ bottom: 20 });
        }

        // 操作按钮
        if (!this.showModifyInput) {
          Row() {
            // 拒绝按钮
            Button($r('app.string.deny'))
              .width('25%')
              .height(50)
              .backgroundColor('#FF5722')
              .onClick(() => {
                this.onDeny();
              });

            // 修改按钮
            Button($r('app.string.modify'))
              .width('25%')
              .height(50)
              .backgroundColor('#FF9800')
              .onClick(() => {
                if (this.request) {
                  this.modifiedCommand = this.request.command;
                }
                this.showModifyInput = true;
              });

            // 允许按钮
            Button($r('app.string.allow'))
              .width('25%')
              .height(50)
              .backgroundColor('#4CAF50')
              .onClick(() => {
                this.onAllow();
              });
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceAround);
        }

        // 关闭按钮
        Button('关闭')
          .width('80%')
          .height(35)
          .backgroundColor('#EEEEEE')
          .fontColor('#888888')
          .margin({ top: 15 })
          .onClick(() => {
            this.onClose();
          });
      }
      .width('85%')
      .padding(25)
      .backgroundColor('#FFFFFF')
      .borderRadius(16)
      .shadow({ radius: 20, color: '#000000', offsetX: 0, offsetY: 5 });
    }
    .width('100%')
    .height('100%');
  }
}