set -x
docker run --rm myimage bash -c "ruby -rrbconfig -e 'puts RbConfig::CONFIG[\"prefix\"]'"
docker run --rm myimage bash -c "ruby -ropenssl -e 'puts OpenSSL::VERSION'"
docker run --rm myimage bash -c "
ruby -ropenssl -e 'puts OpenSSL::VERSION' &&
ruby -rzlib -e 'puts Zlib::VERSION' &&
ruby -ryaml -e 'puts YAML.dump({a: 1})' &&
ruby -e 'require \"readline\"; puts \"readline OK\"' &&
python3 -c 'import ssl; print(ssl.OPENSSL_VERSION)' &&
python3 -c 'import zlib; print(\"zlib OK\", zlib.ZLIB_VERSION)' &&
python3 -c 'import sqlite3; print(\"sqlite3 OK\", sqlite3.sqlite_version)' &&
python3 -c 'import ctypes; print(\"ctypes/libffi OK\")' &&
python3 -c 'import readline; print(\"readline OK\")'
"
