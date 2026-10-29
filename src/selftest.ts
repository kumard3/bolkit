import { File, Paths } from 'expo-file-system';
import { transcribeWithModel } from './asr';
import { modelById } from './asr/registry';

// Hidden device check: drop Documents/selftest.wav on the phone (devicectl copy to) and launch;
// the app's own whisper path writes its transcript to Documents/selftest.json.
export async function runWhisperSelftest(): Promise<void> {
  const wav = new File(Paths.document, 'selftest.wav');
  if (!wav.exists) return;
  const started = Date.now();
  let result: unknown;
  try {
    const res = await transcribeWithModel(wav.uri, modelById('oriserve-swift-q8'), 'en', false);
    result = { ms: Date.now() - started, text: res.text };
  } catch (e) {
    result = { error: String(e) };
  }
  console.log('[selftest]', JSON.stringify(result));
  new File(Paths.document, 'selftest.json').write(JSON.stringify(result));
  wav.delete();
}
