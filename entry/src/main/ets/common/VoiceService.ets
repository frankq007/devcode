/**
 * 语音控制服务 (ArkTS 兼容版本)
 * 
 * 注意: HarmonyOS NEXT API 23 中语音识别 API 可能需要更新
 * 当前保留接口，实际实现待 API 可用后补充
 */
 
import { hilog } from '@kit.PerformanceAnalysisKit';
import { wsService } from './WebSocketService';
 
const DOMAIN = 0xFF00;
const TAG = 'VoiceService';
 
type VoiceResultCallback = (text: string) => void;
 
export class VoiceService {
  private isListening: boolean = false;
  private resultCallbacks: VoiceResultCallback[] = [];
 
  init(): void {
    hilog.info(DOMAIN, TAG, 'Voice service initialized')
    // TODO: 实际语音识别 API 待 HarmonyOS NEXT SDK 更新后实现
  }
 
  startListening(): void {
    if (this.isListening) {
      hilog.warn(DOMAIN, TAG, 'Already listening')
      return
    }
    this.isListening = true
    hilog.info(DOMAIN, TAG, 'Start listening')
    // TODO: 实际语音识别实现
  }
 
  stopListening(): void {
    if (!this.isListening) {
      return
    }
    this.isListening = false
    hilog.info(DOMAIN, TAG, 'Stop listening')
  }
 
  private handlePermissionKeyword(text: string): void {
    const lowerText: string = text.toLowerCase()
    
    if (lowerText.includes('允许') || lowerText.includes('同意') || 
        lowerText.includes('可以') || lowerText.includes('好') ||
        lowerText.includes('yes') || lowerText.includes('确认')) {
      // 需要实际权限ID
      hilog.info(DOMAIN, TAG, 'Voice permission: allow')
      return
    }
    
    if (lowerText.includes('拒绝') || lowerText.includes('不行') ||
        lowerText.includes('不可以') || lowerText.includes('取消') ||
        lowerText.includes('no') || lowerText.includes('否')) {
      hilog.info(DOMAIN, TAG, 'Voice permission: deny')
      return
    }
  }
 
  sendAsCommand(text: string): void {
    if (text !== null && text !== undefined && text.trim().length > 0) {
      wsService.execCommand(text.trim())
      hilog.info(DOMAIN, TAG, `Sent command: ${text}`)
    }
  }
 
  onResult(callback: VoiceResultCallback): void {
    this.resultCallbacks.push(callback)
  }
 
  private notifyResult(text: string): void {
    for (let i = 0; i < this.resultCallbacks.length; i++) {
      const callback = this.resultCallbacks[i]
      callback(text)
    }
  }
 
  getListening(): boolean {
    return this.isListening
  }
 
  release(): void {
    this.stopListening()
    this.resultCallbacks = []
    hilog.info(DOMAIN, TAG, 'Voice service released')
  }
}
 
export const voiceService = new VoiceService();