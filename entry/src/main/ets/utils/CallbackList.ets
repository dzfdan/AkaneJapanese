import appLogger from './Logger';

export class CallbackList<T> {
  private callbacks: T[] = [];

  add(callback: T): void {
    if (this.callbacks.indexOf(callback) === -1) {
      this.callbacks.push(callback);
    }
  }

  remove(callback: T): void {
    const index = this.callbacks.indexOf(callback);
    if (index !== -1) {
      this.callbacks.splice(index, 1);
    }
  }

  size(): number {
    return this.callbacks.length;
  }

  notify(action: (callback: T) => void): void {
    const snapshot = this.callbacks.slice();
    for (const callback of snapshot) {
      try {
        action(callback);
      } catch (err) {
        appLogger.error('CallbackList: subscriber failed', err);
      }
    }
  }
}
