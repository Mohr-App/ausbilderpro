#!/bin/bash
# ═══════════════════════════════════════════════════════
# AusbilderPro Suite – Build & Deploy
# ═══════════════════════════════════════════════════════
# Klartext:      src/*.html   (IMMER im Repo, hier wird entwickelt)
# Obfuscated:    /*.html      (wird auf GitHub Pages deployed)
#
# Workflow:
#   1. Änderungen IMMER in src/*.html machen
#   2. bash build.sh
#   3. git add -A && git commit -m "..." && git push
#
# Falls Claude nicht verfügbar: src/ enthält den kompletten
# lesbaren Quellcode aller 5 Apps.
# ═══════════════════════════════════════════════════════
set -e

APPS="AzubiPro.html MitarbeiterPro.html ArbeitgeberPro.html AusbilderPro.html HBZVerwaltung.html"
SRCDIR="src"

echo ""
echo "═══════════════════════════════════════════"
echo "  AusbilderPro Suite – Build"
echo "═══════════════════════════════════════════"
echo ""
echo "  Klartext:    src/*.html"
echo "  Output:      *.html (obfuscated)"
echo ""

# Check tools
if ! command -v javascript-obfuscator &>/dev/null; then
  echo "⚠ javascript-obfuscator nicht installiert."
  echo "  npm install -g javascript-obfuscator"
  echo ""
  echo "Fallback: Nur Minification (Whitespace entfernen)..."
  OBFUSCATE=0
else
  OBFUSCATE=1
fi

command -v python3 &>/dev/null || { echo "❌ python3 fehlt"; exit 1; }

for APP in $APPS; do
  SRC="$SRCDIR/$APP"
  OUT="$APP"
  
  if [ ! -f "$SRC" ]; then
    echo "⚠ $SRC nicht gefunden, überspringe"
    continue
  fi
  
  echo -n "🔧 $APP ... "
  
  python3 - "$SRC" "$OUT" "$OBFUSCATE" << 'PYEOF'
import re, sys, subprocess, tempfile, os

src_path = sys.argv[1]
out_path = sys.argv[2]
do_obfuscate = sys.argv[3] == '1'

code = open(src_path, 'r', encoding='utf-8').read()

def obfuscate_js(js_code):
    if len(js_code.strip()) < 100:
        return js_code, 'skip'
    
    with tempfile.NamedTemporaryFile(mode='w', suffix='.js', delete=False, encoding='utf-8') as f:
        f.write(js_code)
        tmp_in = f.name
    tmp_out = tmp_in + '.obf.js'
    
    try:
        result = subprocess.run([
            'javascript-obfuscator', tmp_in,
            '--output', tmp_out,
            '--compact', 'true',
            '--control-flow-flattening', 'false',
            '--dead-code-injection', 'false',
            '--string-array', 'true',
            '--string-array-encoding', 'base64',
            '--string-array-threshold', '0.5',
            '--rename-globals', 'false',
            '--self-defending', 'false',
            '--identifier-names-generator', 'hexadecimal',
            '--unicode-escape-sequence', 'false',
            '--target', 'browser',
        ], capture_output=True, text=True, timeout=180)
        
        if result.returncode != 0 or not os.path.exists(tmp_out):
            return js_code, 'fail'
        
        obf = open(tmp_out, 'r', encoding='utf-8').read()
        
        # Syntax-Check via node
        with tempfile.NamedTemporaryFile(mode='w', suffix='.js', delete=False, encoding='utf-8') as chk:
            chk.write(obf)
            chk_path = chk.name
        
        chk_result = subprocess.run(['node', '--check', chk_path], capture_output=True, text=True, timeout=30)
        os.unlink(chk_path)
        
        if chk_result.returncode != 0:
            return js_code, 'syntax-error'
        
        return obf, 'ok'
    except Exception as e:
        return js_code, f'error:{e}'
    finally:
        for f in [tmp_in, tmp_out]:
            if os.path.exists(f): os.unlink(f)

# Process each <script> block
parts = []
last_end = 0
obf_count = 0
min_count = 0
fail_count = 0

for m in re.finditer(r'(<script(?:\s[^>]*)?>)(.*?)(</script>)', code, re.DOTALL):
    tag_open = m.group(1)
    js_body = m.group(2)
    tag_close = m.group(3)
    
    if 'src=' in tag_open or len(js_body.strip()) < 100:
        continue
    
    parts.append(code[last_end:m.start()])
    
    if do_obfuscate:
        obf_js, status = obfuscate_js(js_body)
        if status == 'ok':
            parts.append(tag_open + obf_js + tag_close)
            obf_count += 1
        else:
            # Fallback: minify only
            minified = re.sub(r'//[^\n]*\n', '\n', js_body)  # remove line comments
            minified = re.sub(r'/\*.*?\*/', '', minified, flags=re.DOTALL)  # block comments
            minified = re.sub(r'\n\s*\n', '\n', minified)  # empty lines
            parts.append(tag_open + minified + tag_close)
            min_count += 1
            fail_count += 1
    else:
        minified = re.sub(r'//[^\n]*\n', '\n', js_body)
        minified = re.sub(r'/\*.*?\*/', '', minified, flags=re.DOTALL)
        minified = re.sub(r'\n\s*\n', '\n', minified)
        parts.append(tag_open + minified + tag_close)
        min_count += 1
    
    last_end = m.end()

parts.append(code[last_end:])
result = ''.join(parts)

# Minify HTML
lines = result.split('\n')
out_lines = []
in_script = False
for line in lines:
    if '<script' in line and 'src=' not in line:
        in_script = True
    if '</script>' in line:
        in_script = False
    if not in_script:
        stripped = line.strip()
        if stripped:
            out_lines.append(stripped)
    else:
        out_lines.append(line)
result = '\n'.join(out_lines)

open(out_path, 'w', encoding='utf-8').write(result)

orig = os.path.getsize(src_path)
final = os.path.getsize(out_path)
status_str = f"✓ obfuscated" if obf_count and not fail_count else f"⚡ minified" if not obf_count else f"⚠ {obf_count} obf + {min_count} minified (fallback)"
print(f"{status_str}  ({orig//1024}KB → {final//1024}KB)")
PYEOF
  
done

echo ""
echo "═══════════════════════════════════════════"
echo "  ✓ Build fertig!"
echo ""
echo "  Klartext:    src/*.html  (nie löschen!)"
echo "  Deployed:    *.html      (obfuscated)"
echo ""
echo "  Deploy: git add -A && git commit && git push"
echo "═══════════════════════════════════════════"
