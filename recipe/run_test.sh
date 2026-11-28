#!/bin/bash
set -euxo pipefail

test -f "${PREFIX}/bin/makedepf90"

# The rest runs makedepf90, so skip it when cross-compiling (the target binary
# can't execute on the build host).
if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" == "1" ]]; then
  echo "cross-compilation: skipping run test"
  exit 0
fi

# Regression guard: a submodule must depend on its parent module's object.
# (makedepf90 < 3.0.0 silently dropped this, breaking parallel builds.)
work="$(mktemp -d)"
cd "$work"
printf 'module MDF\n  interface\n    module subroutine s()\n    end subroutine\n  end interface\nend module\n' > mdf.F90
printf 'submodule (MDF) sub\ncontains\n  module subroutine s()\n  end subroutine\nend submodule\n' > sub.F90
makedepf90 sub.F90 mdf.F90 | tee deps.mk
grep -q 'sub.F90 mdf.o' deps.mk

# The out-of-bounds patches. Each check fails on unpatched 3.0.1; four (nesting,
# trailing %, -r, -b) only when it is built with ASan.
# #if nesting past the old 20-slot stack must keep each level's state: the
# #elif at the innermost level must stay skipped.
{ for i in $(seq 25); do echo '#if 1'; done
  printf 'module u\n#ifdef A\n#if 1\n#endif\n#elif 1\n  use wrongmod\n#endif\nend module u\n'
  for i in $(seq 25); do echo '#endif'; done; } > nest.F90
printf 'module wrongmod\nend module wrongmod\n' > wrongmod.f90
makedepf90 -DA nest.F90 wrongmod.f90 | tee nest.mk
grep -q '^nest.o : nest.F90 *$' nest.mk

# An include on a last line with no trailing newline.
: > inc.h
printf "module m\nend module m\ninclude 'inc.h'" > eof.f90
makedepf90 eof.f90 | tee eof.mk
grep -q 'eof.f90 inc.h' eof.mk

# A source path over the old 255-byte module-file buffer.
d="$(printf 'd%.0s' $(seq 100))"
long="$d/$d/$d"
mkdir -p "$long"
printf 'module longmod\nend module\n' > "$long/x.f90"
makedepf90 -m %f.mod "$long/x.f90" | grep -q "$long/x.mod"

# A source name with no suffix, %f in the module-file name, a trailing '%'.
printf 'module nosuf\nend module\n' > nosuf
makedepf90 -m %f.mod nosuf | grep -q 'nosuf.mod'
makedepf90 -m 'x%' mdf.F90 > /dev/null

# %s in -S with a submodule name longer than its parent's (was truncated).
printf 'submodule (MDF) mdf_s01\nend submodule\n' > s01.F90
makedepf90 -s '%m@%s.smod' -S smod.txt s01.F90 mdf.F90 > /dev/null
grep -q 'mdf@mdf_s01.smod' smod.txt

# A joined -rRULE (unchecked by main.c) expanding past the old 1024-byte buffer.
makedepf90 -r"$(printf '%%f %.0s' $(seq 300))" mdf.F90 | grep -q "mdf mdf"

# -b on a name with no directory part (read before the name).
makedepf90 -b d mdf.F90 | grep -q '^d/mdf.o '

# An include name past the 8192-byte string buffer.
printf "program q\ninclude '%s'\nend\n" "$(printf 'z%.0s' $(seq 9000))" > strinc.f90
makedepf90 strinc.f90 > /dev/null
