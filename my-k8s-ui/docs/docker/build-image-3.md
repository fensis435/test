その違和感は正しいです。

私が前の例で出した Makefile は、**コンテナ内で実行する処理と、ホスト側で実行する処理が混ざっています。**
実運用ではあまり良い設計ではありません。

例えばこれ。

```make
verify:
	./scripts/verify-runtime.sh
```

このスクリプトは

```bash
/runtime-root
```

を前提にしています。

しかしホスト側には

```text
/runtime-root
```

は存在しません。

つまり

```bash
make verify
```

をホストで実行しても動きません。

---

## コンテナイメージビルドの世界ではどこで実行するべきか

実際には

```text
ホスト
 └─ docker build
      ↓
 builderコンテナ
      ↓
 verify
      ↓
 sbom
      ↓
 scan
```

です。

つまり

```bash
verify-runtime.sh
create-sbom.sh
scan-vulnerability.sh
```

は

**builderステージの中で実行されるべき**

です。

---

## 私ならこうする

Makefileは

```make
build:
	docker build \
	  -f Dockerfile.runtime \
	  -t runtime:latest .
```

だけに近くなります。

そして

Dockerfile側で

```dockerfile
RUN /scripts/build-runtime-root.sh

RUN /scripts/generate-runtime-rpms.sh

RUN /scripts/verify-runtime.sh

RUN /scripts/create-sbom.sh
```

を実行。

---

## さらによくあるパターン

builderステージ

```dockerfile
FROM almalinux:9 AS builder
```

で

```dockerfile
RUN build-runtime-root.sh
RUN verify-runtime.sh
RUN create-sbom.sh
```

を実施。

---

runtimeステージ

```dockerfile
FROM almalinux:9
```

で

```dockerfile
COPY --from=builder ...
```

だけ。

---

## Makefileは何をするのか

実際には

```make
build:
	docker build -t runtime .

scan:
	trivy image runtime

push:
	docker push runtime
```

みたいになります。

つまり

```text
build-runtime-root.sh
verify-runtime.sh
generate-runtime-rpms.sh
```

は

Makefileから直接呼ばない

です。

---

## CI/CDならこうなる

例えば [GitHub Actions](https://github.com/features/actions?utm_source=chatgpt.com) や [Jenkins](https://www.jenkins.io/?utm_source=chatgpt.com) なら

```text
docker build
   ↓
builder stage
   ↓
verify
   ↓
sbom
   ↓
runtime build
   ↓
trivy image scan
   ↓
push
```

です。

Makefileは単に

```make
build:
	docker build -t runtime .

push:
	docker push runtime
```

程度。

---

## もっと根本的な話

実は案Aの場合、

```text
generate-runtime-rpms.sh
```

すら不要になる可能性があります。

なぜなら

builderで使った

```bash
openssl-devel
readline-devel
sqlite-devel
```

から

runtimeに必要な

```bash
openssl-libs
readline
sqlite-libs
```

を固定で管理できるからです。

RHEL系ではこちらの方が一般的です。

つまり実運用だと、

```text
Dockerfile.builder
 ↓
Python/Rubyビルド

Dockerfile.runtime
 ↓
固定RPMインストール
 ↓
COPY runtime-root
```

になり、

先ほどの

```text
generate-runtime-rpms.sh
verify-runtime.sh
```

すら不要になるケースが多いです。

AlmaLinux9限定で運用するなら、私なら「ELF解析でRPMを導出する仕組み」よりも、「runtimeに入れるRPMリストをコードとして管理する仕組み」を選びます。そちらの方が保守性が高く、ビルドも速く、トラブルシュートもしやすいです。
