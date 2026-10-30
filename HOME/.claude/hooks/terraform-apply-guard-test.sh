#!/bin/bash
# terraform-apply-guard-test.sh: fixture matrix for terraform-apply-guard.sh.
#
# Deny: every mutating verb on terraform, tofu and terragrunt, in every spelling
# a deny rule misses (-chdir, full path, wrapper, `bash -c`, pipeline, chained,
# env prefix, quoted verb), each asserting on the reason text.
# Allow: the read-only verbs Scott uses (plan with -out / -lock=false / -destroy,
# init, validate, fmt, show, output, state list|show|pull) and every place the
# words merely appear (echo, commit message, grep pattern, comment, heredoc).
set -u
export LC_ALL=C

HOOK="$(cd "$(dirname "$0")" && pwd)/terraform-apply-guard.sh"
pass=0
fail=0

assert() { # assert <expect> <label> <out> <want substring>
  local expect="$1" label="$2" out="$3" want="$4" decision reason
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
  if [ "$decision" != "$expect" ]; then
    fail=$((fail + 1))
    printf 'FAIL  [want %s got %s] %s\n      -> %s\n' "$expect" "$decision" "$label" "$reason"
    return
  fi
  if [ -n "$want" ] && ! printf '%s' "$reason" | grep -Fq -- "$want"; then
    fail=$((fail + 1))
    printf 'FAIL  [%s, reason lacks "%s"] %s\n      -> %s\n' "$expect" "$want" "$label" "$reason"
    return
  fi
  pass=$((pass + 1))
  printf 'PASS  [%s] %s\n' "$expect" "$label"
}

run() { # run <expect> <command> [<want>]
  local expect="$1" cmd="$2" want="${3-}" out
  out=$(jq -n --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c},cwd:"/tmp"}' | bash "$HOOK")
  assert "$expect" "$cmd" "$out" "$want"
}

# ---- deny: the mutating verbs, plain
for t in terraform tofu terragrunt; do
  run deny "$t apply" "'apply'"
  run deny "$t apply tfplan" "'apply'"
  run deny "$t destroy" "'destroy'"
  run deny "$t import aws_s3_bucket.b my-bucket" "'import'"
  run deny "$t taint aws_instance.x" "'taint'"
  run deny "$t untaint aws_instance.x" "'untaint'"
  run deny "$t force-unlock abc123" "'force-unlock'"
  run deny "$t refresh" "'refresh'"
  run deny "$t state rm aws_instance.x" "'state rm'"
  run deny "$t state mv a b" "'state mv'"
  run deny "$t state push terraform.tfstate" "'state push'"
  run deny "$t state replace-provider a b" "'state replace-provider'"
  run deny "$t workspace delete dev" "'workspace delete'"
  run deny "$t plan -auto-approve" "'-auto-approve'"
done
run deny "terragrunt apply-all" "'apply-all'"
run deny "terragrunt destroy-all" "'destroy-all'"
run deny "terragrunt run-all apply" "'apply'"
run deny "terragrunt run --all -- apply" "'apply'"

# ---- deny: spellings a Bash(terraform apply:*) rule misses
run deny "terraform -chdir=infra apply" "'apply'"
run deny "/usr/bin/terraform apply" "'apply'"
run deny "~/.local/bin/tofu destroy" "'destroy'"
run deny "aws-vault exec prod -- terraform apply" "'apply'"
run deny "op run -- terraform apply tfplan" "'apply'"
run deny "sudo terraform apply" "'apply'"
run deny "env TF_VAR_x=1 terraform apply" "'apply'"
run deny "TF_LOG=debug terraform apply" "'apply'"
run deny "cd infra && terraform apply -auto-approve" "'apply'"
run deny "terraform plan -out=tfplan; terraform apply tfplan" "'apply'"
run deny "terraform plan | tee out.txt && terraform apply" "'apply'"
run deny "bash -c 'terraform apply'" "'apply'"
run deny 'sh -c "tofu destroy"' "'destroy'"
run deny 'out=$(terraform apply)' "'apply'"
run deny '"terraform" "apply"' "'apply'"
run deny 'terraform "apply"' "'apply'"
run deny 'terraform ap""ply' "'apply'"
run deny "terraform apply -var='x=1' -var-file=prod.tfvars" "'apply'"

# ---- allow: read-only verbs
run allow "terraform plan"
run allow "terraform plan -out=tfplan"
run allow "terraform plan -lock=false"
run allow "terraform plan -lock=false -json"
run allow "terraform plan -destroy"
run allow "terraform plan -target=module.apply"
run allow "tofu plan -out=tfplan"
run allow "terragrunt run-all plan"
run allow "terragrunt plan"
run allow "terraform init"
run allow "terraform init -upgrade"
run allow "terraform validate"
run allow "terraform fmt -recursive"
run allow "terraform show tfplan"
run allow "terraform show -json tfplan"
run allow "terraform output"
run allow "terraform state list"
run allow "terraform state show aws_instance.x"
run allow "terraform state pull"
run allow "terraform workspace list"
run allow "terraform workspace select dev"
run allow "terraform version"
run allow "aws-vault exec prod -- terraform plan"
run allow "cd infra && terraform plan -out=tfplan"
run allow "tflint --recursive"
run allow "terraform-docs markdown ."

# ---- allow: help is a usage page, not a mutation
for t in terraform tofu terragrunt; do
  run allow "$t apply -help"
  run allow "$t apply --help"
  run allow "$t apply -h"
  run allow "$t destroy -help"
  run allow "$t help apply"
  run allow "$t help"
done
run allow "terraform -chdir=/tmp apply -help"
run allow "terraform -chdir=/tmp help apply"
run allow "aws-vault exec prod -- terraform apply -help"
run allow "terraform state rm -help"
run allow "terraform apply -help | head -20"
run allow "terraform apply -help 2>&1 | head -3"

# ---- deny: help must not become a bypass
run deny "terraform apply help" "'apply'"
run deny "terraform apply -auto-approve help" "'apply'"
run deny "terraform plan -help; terraform apply" "'apply'"
run deny "terraform help && terraform destroy" "'destroy'"
run deny "terraform apply -var x=help" "'apply'"

# ---- allow: the words appear, nothing runs
run allow 'echo "terraform apply"'
run allow "echo 'terraform destroy'"
run allow 'git commit -m "fix terraform apply ordering"'
run allow "grep -rn 'terraform apply' docs/"
run allow "rg 'tofu destroy' ."
run allow "# terraform apply"
run allow 'cat <<EOF
terraform apply
EOF'
run allow "ls apply/"
run allow "cat apply.tf"
run allow "git log --oneline -- destroy.tf"
run allow "make apply"
run allow ""

# ---- non-Bash tools pass through
out=$(jq -n '{tool_name:"Read",tool_input:{file_path:"/tmp/apply.tf"}}' | bash "$HOOK")
assert allow "non-Bash tool" "$out" ""

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
