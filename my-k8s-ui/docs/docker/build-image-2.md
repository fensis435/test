案Aを実運用レベルまで持っていくなら、実は「ライブラリを収集する」よりも、

**Python/Rubyをビルド → 必要RPMを自動導出 → SBOM生成 → 脆弱性スキャン → CIで検証**

をパイプライン化する方が重要です。

私なら以下の構成にします。

# 最終構成

```text
.
├── Dockerfile.builder
├── Dockerfile.runtime
├── versions.yaml
├── Makefile
├── scripts
│   ├── build-runtime-root.sh
│   ├── generate-runtime-rpms.sh
│   ├── generate-paths.sh
│   ├── strip-runtime.sh
│   ├── verify-runtime.sh
│   ├── create-sbom.sh
│   └── scan-vulnerability.sh
├── generated
│   ├── runtime-rpms.txt
│   ├── paths.sh
│   └── sbom.spdx.json
└── .github/workflows/build.yml
```

---

# versions.yaml

バージョンをコードから分離。

```yaml
python:
  - 3.12.4
  - 3.13.0

ruby:
  - 3.3.4
  - 3.4.1
```

---

# build-runtime-root.sh

pyenv/rbenvをランタイムへ持ち込まない。

```bash
#!/usr/bin/env bash
set -euo pipefail

OUT=/runtime-root

rm -rf "$OUT"

mkdir -p "$OUT/opt"

cp -a \
  /root/.pyenv/versions \
  "$OUT/opt/python"

cp -a \
  /root/.rbenv/versions \
  "$OUT/opt/ruby"
```

---

# generate-runtime-rpms.sh

RHEL系ではRPM名だけを保持。

バージョン固定しない。

```bash
#!/usr/bin/env bash
set -euo pipefail

OUT=generated/runtime-rpms.txt

mkdir -p generated

TMP=$(mktemp)

find /runtime-root \
  \( \
      -type f -perm /111 \
      -o -name "*.so" \
      -o -name "*.so.*" \
  \) \
| while read -r FILE
do

    ldd "$FILE" 2>/dev/null \
    | awk '
      /=> \// {print $3}
      /^\// {print $1}
    '

done \
| sort -u \
> "$TMP"
```

RPM名へ変換。

```bash
while read -r LIB
do

    rpm -qf "$LIB" \
      --queryformat '%{NAME}\n'

done < "$TMP" \
| sort -u \
> "$OUT"
```

結果

```text
glibc
openssl-libs
libffi
readline
sqlite-libs
libyaml
gdbm-libs
zlib
```

こうすると AlmaLinux9.5 → 9.6 でも追従できる。

---

# generate-paths.sh

PATH問題を解決。

ワイルドカードPATHは禁止。

```bash
#!/usr/bin/env bash
set -euo pipefail

OUT=generated/paths.sh

LATEST_PYTHON=$(
ls /runtime-root/opt/python \
| sort -V \
| tail -1
)

LATEST_RUBY=$(
ls /runtime-root/opt/ruby \
| sort -V \
| tail -1
)

cat > "$OUT" <<EOF
export PATH=/opt/python/${LATEST_PYTHON}/bin:\$PATH
export PATH=/opt/ruby/${LATEST_RUBY}/bin:\$PATH
EOF
```

---

# strip-runtime.sh

サイズ削減。

```bash
#!/usr/bin/env bash
set -euo pipefail

find /runtime-root \
  -type f \
  \( \
    -name "*.so" \
    -o -perm /111 \
  \) \
  -exec strip --strip-unneeded {} \; \
  2>/dev/null \
  || true
```

10〜30%程度削減できる。

---

# verify-runtime.sh

実運用では chroot 検証。

```bash
#!/usr/bin/env bash
set -euo pipefail

FAILED=0

while read -r FILE
do

    if ldd "$FILE" 2>/dev/null \
        | grep -q "not found"
    then

        echo "missing dependency: $FILE"

        FAILED=1
    fi

done < <(
find /runtime-root \
 \( \
   -type f -perm /111 \
   -o -name "*.so" \
   -o -name "*.so.*" \
 \)
)

exit $FAILED
```

---

# create-sbom.sh

SBOMは必須。

[Syft](https://github.com/anchore/syft?utm_source=chatgpt.com)

```bash
#!/usr/bin/env bash
set -euo pipefail

mkdir -p generated

syft dir:/runtime-root \
  -o spdx-json \
  > generated/sbom.spdx.json
```

---

# scan-vulnerability.sh

[Trivy](https://github.com/aquasecurity/trivy?utm_source=chatgpt.com)

```bash
#!/usr/bin/env bash
set -euo pipefail

trivy fs \
  --severity HIGH,CRITICAL \
  /runtime-root
```

CIでは失敗扱い。

---

# Dockerfile.runtime

```dockerfile
FROM almalinux:9

COPY generated/runtime-rpms.txt /tmp/

RUN xargs -a /tmp/runtime-rpms.txt \
    dnf install -y

COPY runtime-root/opt /opt

COPY generated/paths.sh \
     /etc/profile.d/runtime-paths.sh

ENV BUNDLE_SILENCE_ROOT_WARNING=1

CMD ["/bin/bash"]
```

---

# Makefile

```make
build:
	docker build \
	  -f Dockerfile.builder \
	  -t runtime-builder .

verify:
	./scripts/verify-runtime.sh

strip:
	./scripts/strip-runtime.sh

sbom:
	./scripts/create-sbom.sh

scan:
	./scripts/scan-vulnerability.sh
```

---

# CI

例えば [GitHub Actions](https://github.com/features/actions?utm_source=chatgpt.com)。

実行順序は固定。

```text
build
 ↓
verify
 ↓
strip
 ↓
sbom
 ↓
trivy
 ↓
runtime image build
 ↓
push
```

---

# さらに実運用なら追加するもの

### alternatives生成

複数バージョンがあるので

```text
/usr/bin/python
/usr/bin/python3
/usr/bin/ruby
```

を自動生成。

例

```bash
alternatives \
 --install \
 /usr/bin/python \
 python \
 /opt/python/3.13.0/bin/python \
 100
```

---

### pipキャッシュ削除

```bash
find /runtime-root \
 -name __pycache__ \
 -exec rm -rf {} +
```

---

### gemドキュメント削除

```bash
find /runtime-root \
 -name ri \
 -exec rm -rf {} +
```

---

### EOL監視

Python/RubyのEOLをCIで検査。

例:

* Python 3.12
* Python 3.13
* Ruby 3.3
* Ruby 3.4

のサポート期限をチェックし、期限が近ければビルド失敗。

---

### Cosign署名

[Cosign](https://github.com/sigstore/cosign?utm_source=chatgpt.com)

```bash
cosign sign image:tag
```

---

ここまで入れると、

* ビルド再現性
* 脆弱性管理
* SBOM
* イメージ署名
* サイズ削減
* 複数Python/Ruby共存
* AlmaLinux更新追従

まで含めた、RHEL/Alma系で実際に運用できるレベルの共通ランタイム基盤になります。

