#!/bin/bash
set -euxo pipefail

test -f "${PREFIX}/bin/makedepf90"

# Regression guard: a submodule must depend on its parent module's object.
# (makedepf90 < 3.0.0 silently dropped this, breaking parallel builds.)
work="$(mktemp -d)"
cd "$work"
printf 'module MDF\n  interface\n    module subroutine s()\n    end subroutine\n  end interface\nend module\n' > mdf.F90
printf 'submodule (MDF) sub\ncontains\n  module subroutine s()\n  end subroutine\nend submodule\n' > sub.F90
makedepf90 sub.F90 mdf.F90 | tee deps.mk
grep -q 'sub.F90 mdf.o' deps.mk
