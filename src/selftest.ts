import { File, Paths } from 'expo-file-system';
import { catalogModelById } from './asr/catalog';
import { recordTranscribe } from './asr/recordTranscribe';
import { downloadVoz, vozInstalled } from './asr/voz';
import { downloadModel } from './asr/modelManager';
import { isInstalled } from './asr/index';

async function timed(label: string, fn: () => Promise<{ text: string; units: unknown[] }>) {
  const started = Date.now();
  try {
    const res = await fn();
    return { [label]: { ms: Date.now() - started, text: res.text, words: res.units.length, firstWords: res.units.slice(0, 3) } };
  } catch (e) {
    return { [label]: { error: String(e) } };
  }
}

export async function runWhisperSelftest(): Promise<void> {
  const wav = new File(Paths.document, 'selftest.wav');
  if (!wav.exists) return;
  const result: Record<string, unknown> = {};
  const whisper = catalogModelById('whisper:oriserve-swift-q8');
  const voz = catalogModelById('voz');
  if (whisper?.whisper && !isInstalled(whisper.whisper)) await downloadModel(whisper.whisper);
  if (whisper) Object.assign(result, await timed('whisper', () => recordTranscribe(whisper, wav.uri, 'en')));
  if (voz) {
    result.vozWasInstalled = await vozInstalled();
    const dl = Date.now();
    let last = 0;
    try {
      await downloadVoz((r) => {
        if (r - last >= 0.1) {
          last = r;
          console.log('[selftest] voz download', Math.round(r * 100));
        }
      });
      result.vozDownloadMs = Date.now() - dl;
    } catch (e) {
      result.vozDownloadError = String(e);
    }
    Object.assign(result, await timed('vozFirst', () => recordTranscribe(voz, wav.uri, 'en')));
    Object.assign(result, await timed('vozWarm', () => recordTranscribe(voz, wav.uri, 'en')));
  } else {
    result.voz = 'not in catalog';
  }
  console.log('[selftest]', JSON.stringify(result));
  new File(Paths.document, 'selftest.json').write(JSON.stringify(result));
  wav.delete();
}
