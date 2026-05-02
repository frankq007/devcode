/**
 * 权限弹窗组件 (ArkTS 兼容版本)
 * 
 * 注意: 函数类型不能使用 @Prop 装饰器
 */
 
@Component
export struct PermissionDialog {
  @Prop requestId: string = '';
  @Prop command: string = '';
  @Prop explanation: string = '';
  
  // 函数回调不使用装饰器
  onAllow: () => void = () => {};
  onDeny: () => void = () => {};
  onModify: (newCmd: string) => void = (s: string) => {};
  onClose: () => void = () => {};
 
  @State showModifyInput: boolean = false;
  @State modifiedCommand: string = '';
 
  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
        .opacity(0.5)
 
      Column() {
        Text($r('app.string.permission_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 20 })
 
        Column() {
          Text(this.explanation)
            .fontSize(16)
            .fontColor('#FF5722')
            .margin({ bottom: 15 })
 
          Column() {
            Text('命令原文:')
              .fontSize(12)
              .fontColor('#888888')
              .margin({ bottom: 5 })
 
            Text(this.command)
              .fontSize(14)
              .fontFamily('monospace')
              .backgroundColor('#F5F5F5')
              .padding(10)
              .borderRadius(4)
              .width('100%')
          }
          .width('100%')
          .margin({ bottom: 20 })
        }
 
        if (this.showModifyInput) {
          Column() {
            TextInput({ placeholder: '输入修改后的命令', text: this.modifiedCommand })
              .width('100%')
              .height(50)
              .margin({ bottom: 10 })
              .onChange((value: string) => {
                this.modifiedCommand = value
              })
 
            Row() {
              Button('取消修改')
                .width('40%')
                .height(40)
                .backgroundColor('#666666')
                .onClick(() => {
                  this.showModifyInput = false
                  this.modifiedCommand = ''
                })
 
              Button('提交修改')
                .width('40%')
                .height(40)
                .backgroundColor('#4CAF50')
                .onClick(() => {
                  if (this.modifiedCommand.trim().length > 0) {
                    this.onModify(this.modifiedCommand)
                  }
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceAround)
          }
          .width('100%')
          .margin({ bottom: 20 })
        }
 
        if (!this.showModifyInput) {
          Row() {
            Button($r('app.string.deny'))
              .width('25%')
              .height(50)
              .backgroundColor('#FF5722')
              .onClick(() => {
                this.onDeny()
              })
 
            Button($r('app.string.modify'))
              .width('25%')
              .height(50)
              .backgroundColor('#FF9800')
              .onClick(() => {
                this.modifiedCommand = this.command
                this.showModifyInput = true
              })
 
            Button($r('app.string.allow'))
              .width('25%')
              .height(50)
              .backgroundColor('#4CAF50')
              .onClick(() => {
                this.onAllow()
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceAround)
        }
 
        Button('关闭')
          .width('80%')
          .height(35)
          .backgroundColor('#EEEEEE')
          .fontColor('#888888')
          .margin({ top: 15 })
          .onClick(() => {
            this.onClose()
          })
      }
      .width('85%')
      .padding(25)
      .backgroundColor('#FFFFFF')
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
  }
}