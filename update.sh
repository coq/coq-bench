#! /bin/sh -e

remote=$1
branch=$2

cd `dirname $0`
git fetch "$1"
git reset --hard "$remote/$branch"
