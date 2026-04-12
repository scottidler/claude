run_backend=false
run_frontend=false

if [ "${backend}" = "true" ] && [ "${frontend}" = "false" ]; then
  run_backend=true
elif [ "${frontend}" = "true" ] && [ "${backend}" = "false" ]; then
  run_frontend=true
else
  run_backend=true
  run_frontend=true
fi
