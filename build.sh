#!/bin/bash
set -e
APPS="AzubiPro.html MitarbeiterPro.html ArbeitgeberPro.html AusbilderPro.html HBZVerwaltung.html"
echo "═══ AusbilderPro Build ═══"
command -v javascript-obfuscator &>/dev/null || { echo "npm install -g javascript-obfuscator"; exit 1; }

for APP in $APPS; do
  echo -n "🔧 $APP ... "
  python3 - "src/$APP" "$APP" << 'PYEOF'
import re, sys, subprocess, tempfile, os, json

src_path, out_path = sys.argv[1], sys.argv[2]
code = open(src_path, 'r', encoding='utf-8').read()

# Step 1: Extract ALL function names referenced in HTML event handlers
reserved = set()
for m in re.finditer(r'on\w+\s*=\s*"([^"]*)"', code):
    for fn in re.findall(r'([a-zA-Z_][a-zA-Z0-9_]*)\s*\(', m.group(1)):
        reserved.add(fn)

# Also reserve global function declarations (function xyz(...))
for m in re.finditer(r'function\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(', code):
    reserved.add(m.group(1))

# Also reserve global let/const/var names used as functions
for m in re.finditer(r'(?:let|const|var)\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*=', code):
    reserved.add(m.group(1))

reserved_list = sorted(reserved)

def obfuscate_js(js_code):
    if len(js_code.strip()) < 100:
        return js_code, 'skip'
    with tempfile.NamedTemporaryFile(mode='w', suffix='.js', delete=False, encoding='utf-8') as f:
        f.write(js_code); tmp_in = f.name
    tmp_out = tmp_in + '.obf.js'
    try:
        cmd = ['javascript-obfuscator', tmp_in, '--output', tmp_out,
            '--compact', 'true',
            '--control-flow-flattening', 'false',
            '--dead-code-injection', 'false',
            '--string-array', 'false',
            '--rename-globals', 'false',
            '--self-defending', 'false',
            '--identifier-names-generator', 'hexadecimal',
            '--target', 'browser']
        # Add reserved names
        for name in reserved_list:
            cmd.extend(['--reserved-names', name])
        
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
        if r.returncode != 0 or not os.path.exists(tmp_out):
            return js_code, 'fail: ' + r.stderr[:200]
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

parts = []
last_end = 0
obf_count = 0
for m in re.finditer(r'(<script(?:\s[^>]*)?>)(.*?)(</script>)', code, re.DOTALL):
    tag_open, js_body, tag_close = m.group(1), m.group(2), m.group(3)
    if 'src=' in tag_open or len(js_body.strip()) < 100:
        continue
    parts.append(code[last_end:m.start()])
    obf_js, status = obfuscate_js(js_body)
    parts.append(tag_open + obf_js + tag_close)
    last_end = m.end()
    if status == 'ok': obf_count += 1
    elif status != 'skip': print(f'WARN: {status}')

parts.append(code[last_end:])
open(out_path, 'w', encoding='utf-8').write(''.join(parts))
orig = os.path.getsize(src_path)
final = os.path.getsize(out_path)
print(f"{'✓' if obf_count else '⚡'}  reserved:{len(reserved_list)}  ({orig//1024}KB → {final//1024}KB)")
PYEOF
done
echo "═══ Fertig ═══"
