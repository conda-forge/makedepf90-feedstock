# 2.8.8 defines its own bool enum; C23 (GCC 15 default) makes true/false keywords
export CFLAGS="${CFLAGS} -std=gnu17"
./configure --prefix="$PREFIX"
make
make install
