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
