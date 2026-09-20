/**
 * 简单日志封装
 */

export class Logger {
  private tag: string;

  constructor(tag: string) {
    this.tag = tag;
  }

  /**
   * 输出调试日志
   * @param message 日志消息
   * @param args 附加参数
   */
  debug(message: string, ...args: Object[]): void {
    console.log(`[${this.tag}] [DEBUG] ${message}`, ...args);
  }

  /**
   * 输出信息日志
   * @param message 日志消息
   * @param args 附加参数
   */
  info(message: string, ...args: Object[]): void {
    console.log(`[${this.tag}] [INFO] ${message}`, ...args);
  }

  /**
   * 输出警告日志
   * @param message 日志消息
   * @param args 附加参数
   */
  warn(message: string, ...args: Object[]): void {
    console.warn(`[${this.tag}] [WARN] ${message}`, ...args);
  }

  /**
   * 输出错误日志
   * @param message 日志消息
   * @param args 附加参数
   */
  error(message: string, ...args: Object[]): void {
    console.error(`[${this.tag}] [ERROR] ${message}`, ...args);
  }
}

/**
 * 应用默认日志实例
 */
const appLogger: Logger = new Logger('AkaneApp');

export default appLogger;
