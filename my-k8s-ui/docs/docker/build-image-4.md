ここまで来ると、単なる Dockerfile ではなく、

```text
Runtime Build Platform
```

になります。

私なら次のように構成します。

```text
.
├── Dockerfile
├── versions.yaml
├── rpm
│   └── runtime-packages.txt
├── scripts
│   ├── install-python.sh
│   ├── install-ruby.sh
│   ├── create-runtime-root.sh
│   ├── clean-runtime.sh
│   ├── create-alternatives.sh
│   ├── verify-runtimes.sh
│   ├── check-eol.py
│   ├── create-sbom.sh
│   ├── scan-image.sh
│   └── sign-image.sh
├── generated
│   ├── sbom.spdx.json
│   └── eol-report.json
├── Makefile
└── .github
    └── workflows
        └── build.yml
```

---

# EOLチェック

まず

```yaml
python:
  - 3.12.4
  - 3.13.0

ruby:
  - 3.3.4
  - 3.4.1
```

を読む。

---

## check-eol.py

Python公式EOL API

```text
endoflife.date
```

を利用。

※CI実行前提。

```python
import yaml
import requests
import sys
from datetime import date

cfg=yaml.safe_load(open("versions.yaml"))

failed=False

for version in cfg["python"]:

    major_minor=".".join(version.split(".")[:2])

    data=requests.get(
      f"https://endoflife.date/api/python/{major_minor}.json"
    ).json()

    eol=date.fromisoformat(data["eol"])

    if eol < date.today():
        print(f"Python {version} EOL")
        failed=True

for version in cfg["ruby"]:

    major_minor=".".join(version.split(".")[:2])

    data=requests.get(
      f"https://endoflife.date/api/ruby/{major_minor}.json"
    ).json()

    eol=date.fromisoformat(data["eol"])

    if eol < date.today():
        print(f"Ruby {version} EOL")
        failed=True

sys.exit(1 if failed else 0)
```

---

# SBOM生成

利用ツール:

[Syft公式サイト](https://github.com/anchore/syft?utm_source=chatgpt.com)

---

## create-sbom.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

IMAGE="$1"

mkdir -p generated

syft \
  "$IMAGE" \
  -o spdx-json \
  > generated/sbom.spdx.json
```

---

# 脆弱性スキャン

利用ツール:

[Trivy公式サイト](https://github.com/aquasecurity/trivy?utm_source=chatgpt.com)

---

## scan-image.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

IMAGE="$1"

trivy image \
  --exit-code 1 \
  --severity HIGH,CRITICAL \
  "$IMAGE"
```

HIGH以上があればCI失敗。

---

# Cosign署名

利用ツール:

[Cosign公式サイト](https://github.com/sigstore/cosign?utm_source=chatgpt.com)

---

## sign-image.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

IMAGE="$1"

cosign sign \
  --yes \
  "$IMAGE"
```

---

# Runtime検証

既に作成済みの

```bash
verify-runtimes.sh
```

を強化。

---

## verify-runtimes.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

for PY in /runtime-root/opt/python/*/bin/python
do
    echo "checking $PY"

    "$PY" --version

    "$PY" -c "
import ssl
import sqlite3
import bz2
import lzma
import readline
"

done

for RB in /runtime-root/opt/ruby/*/bin/ruby
do
    echo "checking $RB"

    "$RB" --version

    "$RB" -e "
require 'openssl'
require 'yaml'
require 'zlib'
"
done
```

---

# Makefile

ここで全部統合。

```make
IMAGE=python-ruby-runtime

build:
	docker build \
	-t $(IMAGE) .

verify:
	docker run \
	  --rm \
	  $(IMAGE) \
	  python --version

	docker run \
	  --rm \
	  $(IMAGE) \
	  ruby --version

eol:
	python3 scripts/check-eol.py

sbom:
	./scripts/create-sbom.sh $(IMAGE)

scan:
	./scripts/scan-image.sh $(IMAGE)

sign:
	./scripts/sign-image.sh $(IMAGE)

release: \
	eol \
	build \
	verify \
	sbom \
	scan \
	sign
```

---

# CI

例えば [GitHub Actions](https://github.com/features/actions?utm_source=chatgpt.com)。

---

## build.yml

```yaml
name: runtime-build

on:
  push:

jobs:

  build:

    runs-on: ubuntu-latest

    steps:

      - uses: actions/checkout@v4

      - name: EOL
        run: make eol

      - name: Build
        run: make build

      - name: Verify
        run: make verify

      - name: SBOM
        run: make sbom

      - name: Trivy
        run: make scan

      - name: Cosign
        run: make sign
```

---

# runtime-packages.txt の運用

これが実は最重要です。

```text
rpm/runtime-packages.txt
```

は

```text
CODEOWNERS
```

で保護。

例:

```text
rpm/runtime-packages.txt @platform-team
```

GitHubなら

[CODEOWNERS documentation](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners?utm_source=chatgpt.com)

を利用。

これで

```text
openssl-libs
glibc
sqlite-libs
```

などの変更は必ずレビュー対象になります。

---

# 実際のリリースフロー

```text
versions.yaml更新
 ↓
PR作成
 ↓
EOLチェック
 ↓
builder build
 ↓
runtime build
 ↓
python/ruby verify
 ↓
SBOM生成
 ↓
Trivy scan
 ↓
Cosign署名
 ↓
container registry push
 ↓
本番利用
```

この形なら、AlmaLinux 9 ベースで

* Python複数バージョン
* Ruby複数バージョン
* pyenv/rbenvはランタイムに不要
* 依存RPMはコード管理
* EOL管理
* SBOM
* 脆弱性スキャン
* 署名
* CI/CD

まで揃った、企業内共通ランタイムイメージとして運用できる構成になります。
