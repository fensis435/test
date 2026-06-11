案Aの方が、長期運用・セキュリティ・脆弱性対応・SBOM管理の観点で圧倒的に楽です。

## 目標構成

```text
                +----------------+
                |  base image    |
                | AlmaLinux 9    |
                +--------+-------+
                         |
                         v
                +----------------+
                | builder image  |
                | pyenv/rbenv    |
                | gcc make ...   |
                +--------+-------+
                         |
                         v
                +----------------+
                | runtime-root   |
                | Python         |
                | Ruby           |
                +--------+-------+
                         |
          repoqueryで必要RPM抽出
                         |
                         v
                +----------------+
                | runtime image  |
                | 必要RPMのみ    |
                +----------------+
```

重要なのは、

```text
runtime
```

には

```text
gcc
make
pyenv
rbenv
```

を持ち込まないことです。

---

# ディレクトリ構成

```text
project/
├── Dockerfile
├── scripts/
│   ├── collect-runtime.sh
│   ├── generate-runtime-rpms.sh
│   ├── verify-runtime.sh
│   ├── create-sbom.sh
│   └── scan-vulnerability.sh
├── Makefile
└── runtime-root/
```

---

# Builder Dockerfile

```dockerfile
FROM almalinux:9 AS builder

RUN dnf install -y \
    gcc gcc-c++ make \
    git curl wget tar xz \
    openssl-devel \
    readline-devel \
    sqlite-devel \
    zlib-devel \
    libffi-devel \
    libyaml-devel \
    gdbm-devel \
    ncurses-devel \
    findutils \
    which \
    pax-utils \
    dnf-plugins-core

RUN git clone https://github.com/pyenv/pyenv.git \
    /root/.pyenv

ENV PYENV_ROOT=/root/.pyenv
ENV PATH=$PYENV_ROOT/bin:$PATH

RUN git clone https://github.com/rbenv/rbenv.git \
    /root/.rbenv

RUN mkdir -p /root/.rbenv/plugins

RUN git clone \
    https://github.com/rbenv/ruby-build.git \
    /root/.rbenv/plugins/ruby-build

ENV RBENV_ROOT=/root/.rbenv
ENV PATH=$RBENV_ROOT/bin:$RBENV_ROOT/shims:$PATH

RUN pyenv install 3.12.4
RUN pyenv install 3.13.0

RUN /root/.rbenv/bin/rbenv install 3.3.4
RUN /root/.rbenv/bin/rbenv install 3.4.1

COPY scripts /scripts

RUN chmod +x /scripts/*.sh

RUN /scripts/collect-runtime.sh
RUN /scripts/generate-runtime-rpms.sh
RUN /scripts/verify-runtime.sh
```

---

# collect-runtime.sh

pyenv/rbenvは捨てる。

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

結果

```text
/runtime-root
└── opt
    ├── python
    └── ruby
```

---

# generate-runtime-rpms.sh

これが肝です。

```bash
#!/usr/bin/env bash
set -euo pipefail

OUT=/runtime-rpms.txt
TMP=$(mktemp)

find /runtime-root \
  \( \
    -type f -perm /111 \
    -o -name "*.so" \
    -o -name "*.so.*" \
  \) \
| while read -r FILE
do

    lddtree "$FILE" 2>/dev/null \
    | grep '^/' \
    || true

done \
| sort -u \
> "$TMP"
```

---

ライブラリからRPM逆引き

```bash
while read -r LIB
do

    rpm -qf "$LIB"

done < "$TMP" \
| sort -u \
> "$OUT"
```

生成例

```text
glibc-2.34
openssl-libs-3.0.7
libffi-3.4.2
readline-8.1
sqlite-libs-3.34
zlib-1.2.11
libyaml-0.2
gdbm-libs-1.19
```

---

# verify-runtime.sh

依存漏れ検知。

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT=/runtime-root

FAILED=0

find "$ROOT" \
 \( \
   -type f -perm /111 \
   -o -name "*.so" \
   -o -name "*.so.*" \
 \) \
| while read -r FILE
do

    if ldd "$FILE" 2>/dev/null \
        | grep -q "not found"
    then

        echo "missing: $FILE"
        FAILED=1

    fi

done

exit $FAILED
```

※実際には chroot / container 内で検証するよう改良推奨。

---

# Runtime Dockerfile

```dockerfile
FROM almalinux:9

COPY --from=builder \
     /runtime-rpms.txt \
     /tmp/runtime-rpms.txt

RUN xargs -a /tmp/runtime-rpms.txt \
     dnf install -y

COPY --from=builder \
     /runtime-root/opt \
     /opt

ENV PATH=/opt/python/*/bin:$PATH
ENV PATH=/opt/ruby/*/bin:$PATH
```

---

# SBOM生成

おすすめは
[Syft公式サイト](https://github.com/anchore/syft?utm_source=chatgpt.com)

create-sbom.sh

```bash
#!/usr/bin/env bash

syft dir:/runtime-root \
  -o spdx-json \
  > sbom.json
```

---

# 脆弱性スキャン

おすすめは
[Trivy公式サイト](https://github.com/aquasecurity/trivy?utm_source=chatgpt.com)

scan-vulnerability.sh

```bash
#!/usr/bin/env bash

trivy fs \
    /runtime-root
```

または

```bash
trivy image my-runtime-image
```

---

# Makefile

```make
build:
	docker build -t runtime-builder .

sbom:
	./scripts/create-sbom.sh

scan:
	./scripts/scan-vulnerability.sh

verify:
	./scripts/verify-runtime.sh
```

---

## 実運用でさらに追加したい改善

1. **バージョン管理**

   * Python/RubyのバージョンをDockerfile直書きではなく `versions.yaml` に集約

2. **PATH管理**

   * `PATH=/opt/python/*/bin` は実際にはワイルドカード展開されないので、`alternatives` やシムリンク生成スクリプトで管理

3. **strip**

   * `/opt/python/*/lib/*.so`
   * `/opt/ruby/*/lib/*.so`
     に対して `strip --strip-unneeded`

4. **CI**

   * [GitHub Actions](https://github.com/features/actions?utm_source=chatgpt.com) や [Jenkins](https://www.jenkins.io/?utm_source=chatgpt.com) で

     * build
     * verify
     * sbom
     * trivy
       を必須化

5. **最重要**

   * runtime RPMは「ライブラリファイル→rpm -qf」で逆引きするより、
     `repoquery --whatprovides` と組み合わせて **名前固定ではなくパッケージ名ベース** にする方がアップデート耐性が高い。

実際に私がAlmaLinux/RHEL系でやるなら、最終形は「`runtime-rpms.txt` にバージョン付きRPM名を書かず、パッケージ名だけを抽出して runtime 側で最新を解決させる」設計にします。これが運用コストとセキュリティ更新対応のバランスが最も良いです。

