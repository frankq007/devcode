/**
 * 语音控制服务
 * 
 * 功能：
 * - 使用鸿蒙原生 Core Speech Kit 进行语音识别
 * - 将识别结果转换为指令发送
 * - 支持语音授权（允许/拒绝/修改）
 */

import speech from '@ohos.speech';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { wsService } from './WebSocketService';

const DOMAIN = 0xFF00;
const TAG = 'VoiceService';

// 语音识别回调类型
type VoiceResultCallback = (text: string) => void;

export class VoiceService {
  private speechRecognizer: speech.SpeechRecognizer | null = null;
  private isListening: boolean = false;
  private resultCallbacks: VoiceResultCallback[] = [];

  /**
   * 初始化语音识别器
   */
  init(): void {
    try {
      // 创建语音识别器
      this.speechRecognizer = speech.createSpeechRecognizer('continuous');

      // 设置识别结果回调
      this.speechRecognizer.on('result', (result: speech.SpeechRecognizerResult) => {
        hilog.info(DOMAIN, TAG, `Voice result: ${result.result}`);
        
        if (result.result && result.result.length > 0) {
          const text = result.result;
          this.notifyResult(text);
          
          // 检查是否是权限授权关键词
          this.handlePermissionKeyword(text);
        }
      });

      // 设置错误回调
      this.speechRecognizer.on('error', (err: speech.SpeechRecognizerError) => {
        hilog.error(DOMAIN, TAG, `Voice error: ${err.errCode}, ${err.errMessage}`);
        this.isListening = false;
      });

      // 设置开始回调
      this.speechRecognizer.on('start', () => {
        hilog.info(DOMAIN, TAG, 'Voice recognition started');
        this.isListening = true;
      });

      // 设置结束回调
      this.speechRecognizer.on('end', () => {
        hilog.info(DOMAIN, TAG, 'Voice recognition ended');
        this.isListening = false;
      });

      hilog.info(DOMAIN, TAG, 'Voice service initialized');
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Init error: ${e}`);
    }
  }

  /**
   * 开始语音识别
   */
  startListening(): void {
    if (!this.speechRecognizer) {
      this.init();
    }

    if (this.isListening) {
      hilog.warn(DOMAIN, TAG, 'Already listening');
      return;
    }

    try {
      // 配置识别参数
      const config: speech.SpeechRecognizerConfig = {
        language: 'zh-CN',  // 中文
        timeout: 60000,     // 60秒超时
        continuous: true,   // 连续识别
        silenceTimeout: 3000  // 3秒静默超时
      };

      this.speechRecognizer.startListening(config);
      hilog.info(DOMAIN, TAG, 'Start listening');
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Start error: ${e}`);
    }
  }

  /**
   * 停止语音识别
   */
  stopListening(): void {
    if (!this.speechRecognizer || !this.isListening) {
      return;
    }

    try {
      this.speechRecognizer.stopListening();
      this.isListening = false;
      hilog.info(DOMAIN, TAG, 'Stop listening');
    } catch (e) {
      hilog.error(DOMAIN, TAG, `Stop error: ${e}`);
    }
  }

  /**
   * 处理权限授权关键词
   */
  private handlePermissionKeyword(text: string): void {
    const lowerText = text.toLowerCase();

    // 允许关键词
    if (lowerText.includes('允许') || lowerText.includes('同意') || 
        lowerText.includes('可以') || lowerText.includes('好') ||
        lowerText.includes('yes') || lowerText.includes('确认')) {
      wsService.replyPermission('current', 'y');
      hilog.info(DOMAIN, TAG, 'Voice permission: allow');
      return;
    }

    // 拒绝关键词
    if (lowerText.includes('拒绝') || lowerText.includes('不行') ||
        lowerText.includes('不可以') || lowerText.includes('取消') ||
        lowerText.includes('no') || lowerText.includes('否')) {
      wsService.replyPermission('current', 'n');
      hilog.info(DOMAIN, TAG, 'Voice permission: deny');
      return;
    }
  }

  /**
   * 发送识别结果作为指令
   */
  sendAsCommand(text: string): void {
    if (text && text.trim().length > 0) {
      wsService.execCommand(text.trim());
      hilog.info(DOMAIN, TAG, `Sent command: ${text}`);
    }
  }

  /**
   * 注册结果回调
   */
  onResult(callback: VoiceResultCallback): void {
    this.resultCallbacks.push(callback);
  }

  /**
   * 通知结果
   */
  private notifyResult(text: string): void {
    this.resultCallbacks.forEach(cb => cb(text));
  }

  /**
   * 获取监听状态
   */
  getListening(): boolean {
    return this.isListening;
  }

  /**
   * 释放资源
   */
  release(): void {
    if (this.speechRecognizer) {
      this.stopListening();
      this.speechRecognizer = null;
    }
    this.resultCallbacks = [];
    hilog.info(DOMAIN, TAG, 'Voice service released');
  }
}

// 全局语音服务实例
export const voiceService = new VoiceService();