#! /bin/bash

# Unfortunatelly, "opam install ..." sometimes transiently fails with the following:
#
#     [ERROR] The sources of the following couldn't be obtained, aborting:
#
# We use the following command to overcome this problem.

while true; do
    bash -c "opam install $*" && break
    sleep 10
done
