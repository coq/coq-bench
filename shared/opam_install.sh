#! /bin/bash

# Unfortunatelly, "opam install ..." sometimes transiently fails with the following:
#
#     [ERROR] The sources of the following couldn't be obtained, aborting:
#
# We use the following command to overcome this problem.

echo DEBUG B01
while true; do
    echo DEBUG B02
    bash -c "opam install $*"

    opam_install_exit_status=$?
    echo DEBUG: opam_install.sh: opam_install_exit_status = $opam_install_exit_status
    echo DEBUG B03
    echo DEBUG: opam_install.sh: which coqtop = `which coqtop`
    echo DEBUG B04

    # See also:
    #
    #   https://github.com/ocaml/opam/issues/2894
    #
    case $opam_install_exit_status in
        0)
            # Installation was successful.
            exit 0
            ;;
        66)
            # Unfortunatelly, there are several different situations when we get this exit code from "opam install"
            #
            # 1. when a given package does not exist at all
            #
            # 2. when the information provided in the "url" file is incorrect and given artifact cannot be downloaded
            #
            # 3. the information provided in the "url" file is correct, but due to transient networking problems, download failed.

            # We assume that (3) happened.

            sleep 10
            continue
            ;;
        *)
            # This happens (among other situations) when a given package cannot be compiled.
            exit 1
            ;;
    esac
    echo DEBUG B05
done
echo DEBUG B06
