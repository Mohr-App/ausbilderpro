#!/bin/bash
set -e
APPS="AzubiPro.html MitarbeiterPro.html ArbeitgeberPro.html AusbilderPro.html HBZVerwaltung.html"
echo "═══ AusbilderPro Build ═══"
command -v javascript-obfuscator &>/dev/null || { echo "npm install -g javascript-obfuscator"; exit 1; }

for APP in $APPS; do
  echo -n "🔧 $APP ... "
  python3 - "src/$APP" "$APP" << 'PYEOF'
import re, sys, subprocess, tempfile, os

src_path, out_path = sys.argv[1], sys.argv[2]
code = open(src_path, 'r', encoding='utf-8').read()

def obfuscate_js(js_code):
    if len(js_code.strip()) < 100:
        return js_code, 'skip'
    with tempfile.NamedTemporaryFile(mode='w', suffix='.js', delete=False, encoding='utf-8') as f:
        f.write(js_code); tmp_in = f.name
    tmp_out = tmp_in + '.obf.js'
    try:
        r = subprocess.run(['javascript-obfuscator', tmp_in, '--output', tmp_out,
            '--compact', 'true', '--control-flow-flattening', 'false',
            '--dead-code-injection', 'false', '--string-array', 'true',
            '--string-array-encoding', 'base64', '--string-array-threshold', '0.5',
            '--rename-globals', 'false', '--self-defending', 'false',
            '--identifier-names-generator', 'hexadecimal',
            '--unicode-escape-sequence', 'false', '--target', 'browser'],
            capture_output=True, text=True, timeout=180)
        if r.returncode != 0 or not os.path.exists(tmp_out):
            return js_code, 'fail'
        obf = open(tmp_out, 'r', encoding='utf-8').read()
        # Syntax check
        with tempfile.NamedTemporaryFile(mode='w', suffix='.js', delete=False, encoding='utf-8') as chk:
            chk.write(obf); chk_path = chk.name
        cr = subprocess.run(['node', '--check', chk_path], capture_output=True, text=True, timeout=30)
        os.unlink(chk_path)
        if cr.returncode != 0:
            return js_code, 'syntax-error'
        return obf, 'ok'
    except Exception as e:
        return js_code, f'error:{e}'
    finally:
        for f in [tmp_in, tmp_out]:
            if os.path.exists(f): os.unlink(f)

# Replace each inline <script>...</script> with obfuscated version
# CRITICAL: Preserve HTML structure and tag order exactly!
parts = []
last_end = 0
obf_count = 0

for m in re.finditer(r'(<script(?:\s[^>]*)?>)(.*?)(</script>)', code, re.DOTALL):
    tag_open = m.group(1)
    js_body = m.group(2)
    tag_close = m.group(3)
    
    # Skip external scripts (src=...)
    if 'src=' in tag_open:
        continue
    # Skip tiny scripts
    if len(js_body.strip()) < 100:
        continue
    
    parts.append(code[last_end:m.start()])
    obf_js, status = obfuscate_js(js_body)
    parts.append(tag_open + obf_js + tag_close)
    last_end = m.end()
    if status == 'ok': obf_count += 1

parts.append(code[last_end:])
result = ''.join(parts)

# NO HTML reordering - just write as-is
open(out_path, 'w', encoding='utf-8').write(result)
orig = os.path.getsize(src_path)
final = os.path.getsize(out_path)
print(f"{'✓ obfuscated' if obf_count else '⚡ minified'}  ({orig//1024}KB → {final//1024}KB)")
PYEOF
done
echo "═══ Build fertig! ═══"
