#!/bin/bash
# shapes.sh: the shared shape-mutation list every guard matrix re-runs its
# irreversible deny fixtures through. Sourced by the *-test.sh matrices, never
# run, and never registered as a hook.
#
# Why it exists. The 2026-09-14 implementation audit measured 22 deny-to-allow
# flips across three guards, and every one of them was the SAME defect: the
# command word was not the first word of the statement, because a brace group,
# an `if`, a wrapper, a quote, an `eval` or a process substitution sat in front
# of it. None of the 402 fixtures then in the tree wrapped a gated command in
# any compound-command syntax, so the matrices could not see the class at all.
#
# Pinning twenty more one-off fixtures would not fix that: it would pin the
# twenty shapes someone thought of. A gate that denies `git reset --hard` has to
# deny it in every syntax bash offers for running the same command, so each
# matrix asserts exactly that, over one list defined once. A new shape is added
# HERE and all four matrices gain it on the next run.
#
# WRAPPER_SHAPES entries are printf FORMATS: the single %s is the command.

WRAPPER_SHAPES=(
  '( %s )'
  '{ %s; }'
  'if true; then %s; fi'
  'for i in 1; do %s; done'
  'while false; do :; done; %s'
  'case a in a) %s;; esac'
  'eval "%s"'
  "eval '%s'"
  'timeout 5 %s'
  'time %s'
  '! %s'
  'nohup %s'
  'bash -c "%s"'
  "bash -lc '%s'"
  'echo <(%s)'
  'f(){ %s; }; f'
)

# Every spelling of <command> that runs the same command, one per line. The last
# two mutate the VERB rather than wrap the statement, which is the other half of
# the same class: bash strips the quoting before it decides what to execute, so
# `\git push` and `"git" push` are `git push`.
#
# A command carrying a single quote or a newline cannot ride the quoted shapes,
# so fixtures fed to this are the plain ones.
wrap_shapes() { # wrap_shapes <command>
  local cmd="$1" shape verb rest
  for shape in "${WRAPPER_SHAPES[@]}"; do
    # shellcheck disable=SC2059  # the shape IS the format; that is the point
    printf "$shape\n" "$cmd"
  done
  verb="${cmd%% *}"
  rest="${cmd#"$verb"}"
  printf '\\%s\n' "$cmd"
  printf '"%s"%s\n' "$verb" "$rest"
}
