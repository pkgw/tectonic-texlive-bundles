#! /bin/bash
# Copyright 2016-2020 the Tectonic Project.
# Licensed under the MIT License.
#
# This is the "entrypoint" script for the TeXLive bundler image. When a user runs
# "docker run texlive-bundler foo bar", we are invoked with $1=foo and $2=bar.

set -e

if [ -z "$1" -o "$1" = help ] ; then
    echo "You must supply a subcommand to run in the container. Commands are:

bash              -- Run a bash shell
install-profile   -- Create an installation based on a TeXLive \"profile\" template.
python            -- Run a Python script
update-containers -- Rebuild the TeXLive \"container\" files

Use 'docker run --rm -it bundlercontainer bash' to launch an interactive
shell within a long-running container.
"
    exit 1
fi

command="$1"
shift


function _precise_version () {
    # Log the precise version of the TeXLive tree that we are using. This is
    # done by making files named GITHASH and SVNREV in a directory named in
    # $1. We exit with an error if the tree is not pristine. This must be run
    # from a directory inside the Git repository.

    destdir="$1"

    if ! git update-index -q --refresh ; then
        echo >&2 "error: git update-index failed"
        exit 1
    fi

    if [ -n "$(git diff-index --name-only HEAD --)" ] ; then
        echo >&2 "error: refusing to make packages from dirty working tree"
        exit 1
    fi

    git show-ref --head |head -n1 |awk '{print $1}' >"$destdir/GITHASH"
    git show -s |grep git-svn-id |sed -e 's/.*@//' -e 's/ .*//' >"$destdir/SVNREV"
}


function install_profile () {
    profile_template="$1"
    shift
    install_dest="$1"
    shift
    chown_spec="$1"
    shift

    profile="$(mktemp)"
    sed -e "s|@dest@|$install_dest|g" <"$profile_template" >"$profile"

    cd /state/repo/
    _precise_version "$install_dest"
    Master/install-tl --repository /state/containers --profile "$profile"
    chown -R "$chown_spec" "$install_dest"
}


function OLD_install_profile () {
    profile="$1"
    shift
    install_dest="$1"
    shift
    chown_spec="$1"
    shift

    cd /state/repo/
    _precise_version "$install_dest"
    Master/install-tl --repository /state/containers --profile "$profile"

    if [ $# -gt 0 ] ; then
        cd "$install_dest"
        # NOTE: leading "./" is essential!
        ./bin/*/tlmgr --repository /state/containers install "$@"
    fi

    chown -R "$chown_spec" "$install_dest"
}

function update_containers () {
    cd /state/repo/
    _precise_version /state/containers

    args=(--all --gpgcmd=true --location /state/containers)
    if [ ! -e /state/containers/tlpkg/texlive.tlpdb ] ; then
        args+=(--recreate)
    fi

    exec Master/tlpkg/bin/tl-update-containers "${args[@]}"
}


# Dispatch subcommands.

if [ "$command" = bash ] ; then
    exec bash "$@"
elif [ "$command" = python ] ; then
    exec python3 "$@"
elif [ "$command" = install-profile ] ; then
    install_profile "$@"
elif [ "$command" = update-containers ] ; then
    update_containers "$@"
else
    echo "$0: unrecognized command \"$command\"."
    exit 1
fi