import { NativeEventEmitter, NativeModules, Platform } from 'react-native';
import type { TimedUnit } from './types';

type Native = {
  isDownloaded(): Promise<boolean>;
  download(): Promise<void>;
  remove(): Promise<void>;
  transcribeFile(path: string, vocabulary: string[]): Promise<{ text: string; units: TimedUnit[]; processingMs: number }>;
};

const native = Platform.OS === 'ios' ? (NativeModules.ScribeVoz as Native | undefined) : undefined;

export const VOZ_SIZE_BYTES = 321_000_000;
export const VOZ_CREDIT = 'Powered by Desert Ant Labs';

export function vozSupported(): boolean {
  return !!native && parseInt(String(Platform.Version), 10) >= 18;
}

export async function vozInstalled(): Promise<boolean> {
  return native ? native.isDownloaded().catch(() => false) : false;
}

export async function downloadVoz(onProgress?: (ratio: number) => void, signal?: AbortSignal): Promise<void> {
  if (!native) throw new Error('Voz is unavailable on this device');
  const sub = new NativeEventEmitter(NativeModules.ScribeVoz).addListener('ScribeVoz', (e: { type: string; fraction: number }) => {
    if (e.type === 'progress') onProgress?.(e.fraction);
  });
  try {
    const job = native.download();
    if (signal) {
      await Promise.race([
        job,
        new Promise<never>((_, reject) => {
          signal.addEventListener('abort', () => reject(new Error('Download cancelled')));
        }),
      ]);
    } else {
      await job;
    }
  } finally {
    sub.remove();
  }
}

export async function deleteVoz(): Promise<void> {
  await native?.remove();
}

export function transcribeWithVoz(uri: string, vocabulary: string[] = []): Promise<{ text: string; units: TimedUnit[]; processingMs: number }> {
  if (!native) return Promise.reject(new Error('Voz is unavailable on this device'));
  return native.transcribeFile(uri.replace(/^file:\/\//, ''), vocabulary);
}
